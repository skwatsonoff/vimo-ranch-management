// VIMO's own ear: speech to text inside the browser, with no speech service.
//
// Apple's browser speech service has no Tamil, and is blocked altogether in
// a Home Screen web app. This ear records with the microphone, finds where
// speech starts and ends itself, and writes it down with a Whisper model
// that runs on the phone (transformers.js, 8-bit ONNX, WebAssembly). The
// model is downloaded once (from this app's GitHub "voice-models" branch, or
// Hugging Face for English) and kept in the browser's cache.
//
// Dart talks to it through window.vimoEar (lib/voice_ear_web.dart).
(function () {
  'use strict';
  const LIB = 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.3.1';
  const OWN = 'https://raw.githubusercontent.com/skwatsonoff/vimo-ranch-management/voice-models/';
  // Cactus Compute's engine (Apache-2.0) and its 17 MB English speech model
  // "Whistle", pinned to the versions VIMO was checked with.
  const CACTUS_JS = 'https://huggingface.co/Cactus-Compute/cactus/resolve/a30ea9d3d8619ec5728c66fb7cde6c48ba681b55/releases/4.0.0/wasm/cactus.js';
  const CACTUS_WASM = 'https://huggingface.co/Cactus-Compute/cactus/resolve/a30ea9d3d8619ec5728c66fb7cde6c48ba681b55/releases/4.0.0/wasm/cactus.wasm';
  const WHISTLE = 'https://huggingface.co/Cactus-Compute/whistle/resolve/ad73f1468dd5203791e0cc81d31544c553563645/whistle.cact';
  const EAR_CACHE = 'vimo-ear-v1';
  const RATE = 16000;

  let lib = null;
  const pipes = {}; // model -> Promise<pipeline>
  let stream = null;
  let context = null;
  let source = null;
  let processor = null;
  let listening = false;
  let callbacks = {};
  let language = 'tamil';
  let model = '';
  let keywords = '';

  // Speech finding: a running noise floor and a short memory before speech.
  let floor = 0.004;
  let speech = [];
  let preroll = [];
  let inSpeech = false;
  let loudFrames = 0;
  let quietMs = 0;
  let speechMs = 0;
  const queue = [];
  let busy = false;

  function call(name, value) {
    const f = callbacks[name];
    if (typeof f === 'function') {
      try { f(value); } catch (e) { console.warn('vimoEar callback', e); }
    }
  }

  async function loadLib() {
    if (!lib) {
      lib = await import(LIB);
      lib.env.allowLocalModels = false;
      lib.env.useBrowserCache = true;
    }
    return lib;
  }

  function hostFor(name) {
    return name.includes('/') ? 'https://huggingface.co/' : OWN;
  }

  // --- Whisper through transformers.js (Tamil and other languages) ---------
  async function whisperEngine(name, onProgress) {
    const t = await loadLib();
    const own = !name.includes('/');
    t.env.remoteHost = hostFor(name);
    t.env.remotePathTemplate = own ? '{model}/' : '{model}/resolve/{revision}/';
    try { t.env.backends.onnx.wasm.proxy = true; } catch (e) {}
    const files = {};
    const progress = (p) => {
      if (!p || !p.file) return;
      if (p.status === 'progress' || p.status === 'done') {
        files[p.file] = { loaded: p.loaded || p.total || 0, total: p.total || p.loaded || 0 };
        let loaded = 0, total = 0;
        for (const k in files) { loaded += files[k].loaded; total += files[k].total; }
        if (onProgress) onProgress(total > 0 ? loaded / total : 0, loaded, total);
      }
    };
    const asr = await t.pipeline('automatic-speech-recognition', name, {
      dtype: 'q8',
      device: 'wasm',
      progress_callback: progress,
    });
    return {
      async transcribe(audio, lang) {
        const result = await asr(audio, { language: lang, task: 'transcribe' });
        return (result && result.text ? result.text : '').trim();
      },
    };
  }

  // --- Cactus Whistle (English), in a worker so the screen never stalls ----
  async function cachedBytes(url, onProgress, share) {
    const cache = await caches.open(EAR_CACHE);
    let response = await cache.match(url);
    if (!response) {
      const fresh = await fetch(url);
      if (!fresh.ok) throw new Error('download ' + fresh.status);
      const total = +fresh.headers.get('content-length') || 0;
      const reader = fresh.body.getReader();
      const parts = [];
      let loaded = 0;
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        parts.push(value);
        loaded += value.length;
        if (onProgress && total) onProgress(loaded / total, share);
      }
      const blob = new Blob(parts);
      await cache.put(url, new Response(blob, { headers: { 'content-type': 'application/octet-stream' } }));
      return await blob.arrayBuffer();
    }
    return await response.arrayBuffer();
  }

  const WORKER = `
    let M = null, out = 0;
    const CAP = 65536;
    function str(s) {
      const b = new TextEncoder().encode(s + '\\0');
      const p = M._malloc(b.length);
      M.HEAPU8.set(b, p);
      return p;
    }
    onmessage = async (e) => {
      const d = e.data;
      try {
        if (d.type === 'init') {
          importScripts(d.script);
          M = await createCactus({ wasmBinary: new Uint8Array(d.wasm) });
          const bytes = new Uint8Array(d.model);
          const mp = M._malloc(bytes.length);
          M.HEAPU8.set(bytes, mp);
          if (M._cactus_load(mp, BigInt(bytes.length)) !== 0) throw new Error(M.UTF8ToString(M._cactus_last_error()) || 'load failed');
          out = M._malloc(CAP);
          postMessage({ id: d.id, ok: true });
        } else if (d.type === 'transcribe') {
          const f = d.pcm;
          const pp = M._malloc(f.length * 4);
          new Float32Array(M.HEAPU8.buffer, pp, f.length).set(f);
          const lp = str(d.language), kp = str(d.keywords || '');
          const n = M._cactus_transcribe(pp, f.length, lp, kp, 0, out, CAP);
          M._free(pp); M._free(lp); M._free(kp);
          if (n < 0) throw new Error(M.UTF8ToString(M._cactus_last_error()) || 'transcribe failed');
          postMessage({ id: d.id, ok: true, result: JSON.parse(M.UTF8ToString(out)) });
        }
      } catch (err) {
        postMessage({ id: d.id, ok: false, error: String(err && err.message ? err.message : err) });
      }
    };`;

  async function cactusEngine(onProgress) {
    const share = { wasm: 0, model: 0 };
    const report = () => onProgress && onProgress(share.wasm * 0.07 + share.model * 0.93);
    const [script, wasm, modelBytes] = await Promise.all([
      // Kept in the cache too, so the ear starts with no internet.
      cachedBytes(CACTUS_JS),
      cachedBytes(CACTUS_WASM, (f) => { share.wasm = f; report(); }),
      cachedBytes(WHISTLE, (f) => { share.model = f; report(); }),
    ]);
    const scriptUrl = URL.createObjectURL(new Blob([script], { type: 'text/javascript' }));
    const worker = new Worker(URL.createObjectURL(new Blob([WORKER], { type: 'text/javascript' })));
    let next = 0;
    const waiting = {};
    worker.onmessage = (e) => {
      const w = waiting[e.data.id];
      delete waiting[e.data.id];
      if (w) (e.data.ok ? w.resolve(e.data.result) : w.reject(new Error(e.data.error)));
    };
    const ask = (msg, transfer) => new Promise((resolve, reject) => {
      const id = ++next;
      waiting[id] = { resolve, reject };
      worker.postMessage({ ...msg, id }, transfer || []);
    });
    await ask({ type: 'init', script: scriptUrl, wasm, model: modelBytes }, [wasm, modelBytes]);
    if (onProgress) onProgress(1);
    return {
      async transcribe(audio, lang, words) {
        const r = await ask({ type: 'transcribe', pcm: audio, language: lang === 'english' ? 'en' : lang, keywords: words || '' });
        return (r && r.text ? r.text : '').trim();
      },
    };
  }

  function getEngine(name, onProgress) {
    if (!pipes[name]) {
      pipes[name] = name === 'cactus:whistle' ? cactusEngine(onProgress) : whisperEngine(name, onProgress);
      pipes[name].catch(() => { delete pipes[name]; });
    }
    return pipes[name];
  }

  // Is the model already in the browser's cache? (No download needed.)
  async function isCached(name) {
    try {
      if (name === 'cactus:whistle') {
        const cache = await caches.open(EAR_CACHE);
        return !!(await cache.match(WHISTLE)) && !!(await cache.match(CACTUS_WASM)) && !!(await cache.match(CACTUS_JS));
      }
      const cache = await caches.open('transformers-cache');
      const keys = await cache.keys();
      const base = hostFor(name) + name;
      return keys.some((r) => r.url.startsWith(base) && r.url.includes('decoder_model_merged'));
    } catch (e) {
      return false;
    }
  }

  function rms(frame) {
    let s = 0;
    for (let i = 0; i < frame.length; i++) s += frame[i] * frame[i];
    return Math.sqrt(s / frame.length);
  }

  function resample(input, from) {
    if (from === RATE) return Float32Array.from(input);
    const ratio = from / RATE;
    const out = new Float32Array(Math.floor(input.length / ratio));
    for (let i = 0; i < out.length; i++) {
      const x = i * ratio;
      const a = Math.floor(x);
      const b = Math.min(a + 1, input.length - 1);
      out[i] = input[a] + (input[b] - input[a]) * (x - a);
    }
    return out;
  }

  function onAudio(event) {
    if (!listening) return;
    const frame = resample(event.inputBuffer.getChannelData(0), context.sampleRate);
    const ms = (frame.length / RATE) * 1000;
    const level = rms(frame);
    call('onLevel', Math.min(10, level * 120));
    const threshold = Math.max(floor * 2.6, 0.011);
    const loud = level > threshold;
    if (!inSpeech) {
      // The floor follows the room's noise while nobody speaks.
      floor = floor * 0.95 + Math.min(level, 0.05) * 0.05;
      preroll.push(frame);
      if (preroll.length > 6) preroll.shift();
      loudFrames = loud ? loudFrames + 1 : 0;
      if (loudFrames >= 2) {
        inSpeech = true;
        speech = preroll.slice();
        preroll = [];
        quietMs = 0;
        speechMs = 0;
        call('onSpeech', true);
      }
      return;
    }
    speech.push(frame);
    speechMs += ms;
    quietMs = loud ? 0 : quietMs + ms;
    if (quietMs > 850 || speechMs > 14000) finishSpeech();
  }

  function finishSpeech() {
    inSpeech = false;
    loudFrames = 0;
    call('onSpeech', false);
    const parts = speech;
    speech = [];
    if (speechMs - quietMs < 280) return; // a knock or a cough
    let length = 0;
    for (const p of parts) length += p.length;
    const audio = new Float32Array(length);
    let at = 0;
    for (const p of parts) { audio.set(p, at); at += p.length; }
    queue.push({ audio, language, model, keywords });
    pump();
  }

  async function pump() {
    if (busy || queue.length === 0) return;
    busy = true;
    const job = queue.shift();
    call('onThinking', true);
    try {
      const engine = await getEngine(job.model);
      const started = performance.now();
      const text = await engine.transcribe(job.audio, job.language, job.keywords);
      call('onText', JSON.stringify({ text, ms: Math.round(performance.now() - started), seconds: job.audio.length / RATE }));
    } catch (e) {
      call('onError', String(e && e.message ? e.message : e));
    } finally {
      busy = false;
      call('onThinking', false);
      pump();
    }
  }

  async function openMic() {
    if (stream) return;
    stream = await navigator.mediaDevices.getUserMedia({
      audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true },
    });
    const Ctx = window.AudioContext || window.webkitAudioContext;
    try {
      context = new Ctx({ sampleRate: RATE });
    } catch (e) {
      context = new Ctx();
    }
    source = context.createMediaStreamSource(stream);
    processor = context.createScriptProcessor(1024, 1, 1);
    processor.onaudioprocess = onAudio;
    source.connect(processor);
    processor.connect(context.destination);
  }

  window.vimoEar = {
    supported() {
      return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia && window.WebAssembly);
    },
    isCached(name) {
      return isCached(name);
    },
    // Is [name] published (VIMO's own models live on the voice-models branch)?
    async isAvailable(name) {
      if (name.includes('/') || name.includes(':')) return true;
      try {
        const r = await fetch(OWN + name + '/config.json', { method: 'HEAD', cache: 'no-store' });
        return r.ok;
      } catch (e) {
        return false;
      }
    },
    // Downloads (once) and loads [name]; onProgress(fraction, loadedBytes, totalBytes).
    async prepare(name, onProgress) {
      // Progress is only shown: a problem showing it never stops the download.
      const safe = (f) => { try { if (onProgress) onProgress(f); } catch (e) {} };
      await getEngine(name, safe);
      return true;
    },
    // [words]: names to listen for (the cows), comma separated.
    async start(name, lang, cbs, words) {
      model = name;
      language = lang || 'tamil';
      keywords = words || '';
      callbacks = cbs || {};
      await openMic();
      if (context.state === 'suspended') await context.resume();
      // The iPhone keeps sound stopped until a tap: say so, the app asks.
      if (context.state !== 'running') throw new Error('audio suspended');
      inSpeech = false;
      speech = [];
      preroll = [];
      loudFrames = 0;
      listening = true;
      return true;
    },
    // Stops listening but keeps the microphone open (no new permission
    // question on the iPhone); what was being said is dropped.
    pause() {
      listening = false;
      inSpeech = false;
      speech = [];
      queue.length = 0;
    },
    close() {
      listening = false;
      queue.length = 0;
      try { processor && processor.disconnect(); } catch (e) {}
      try { source && source.disconnect(); } catch (e) {}
      try { stream && stream.getTracks().forEach((t) => t.stop()); } catch (e) {}
      try { context && context.close(); } catch (e) {}
      stream = context = source = processor = null;
    },
  };
})();
