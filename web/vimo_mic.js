// VIMO microphone capture for the web app (Safari, the iPhone Home Screen
// app, Chrome). It only captures: it finds where speech starts and ends and
// hands each finished sentence to Dart as a short 16 kHz WAV held in memory.
// Speech-to-text happens elsewhere (lib/voice_capture_engine.dart).
//
// Rules this file keeps (see lib/voice_capture.dart for the Dart side):
// * One owner. Every start gets a generation number; anything that arrives
//   for an older generation is dropped, and a late getUserMedia stream is
//   stopped at once.
// * start() must be called synchronously from the owner's tap: the
//   AudioContext is created and resumed inside that gesture, before any
//   await, so Safari treats it as user-activated.
// * "Listening" is only reported after a live, unmuted track has delivered
//   real audio frames. A bounded watchdog reports "no-frames" otherwise.
// * Any interruption (audio session interrupted, track muted or ended,
//   audio context suspended or interrupted, page hidden, page hide, input
//   route change) stops capture completely, discards every buffer, and is
//   reported once. Nothing restarts by itself: the owner taps Resume.
// * Nothing is stored: no CacheStorage, IndexedDB, localStorage or files.
(function () {
  'use strict';

  const RATE = 16000;
  const WATCHDOG_MS = 4000;
  const MAX_SPEECH_MS = 14000;
  const END_SILENCE_MS = 850;
  const MIN_SPEECH_MS = 280;
  const PREROLL_FRAMES = 6;

  const WORKLET = `
    class VimoTap extends AudioWorkletProcessor {
      process(inputs) {
        const ch = inputs[0] && inputs[0][0];
        if (ch && ch.length) this.port.postMessage(ch.slice(0));
        return true;
      }
    }
    registerProcessor('vimo-tap', VimoTap);`;

  let gen = 0;            // the active generation (0 = none)
  let phase = 'idle';     // idle | starting | ready | gated | interrupted | stopped | error
  let onEvent = null;     // function(json)
  let onSegment = null;   // function(gen, Uint8Array wav, seconds)
  let stream = null;
  let track = null;
  let context = null;
  let source = null;
  let node = null;        // AudioWorkletNode or ScriptProcessorNode
  let sink = null;        // silent gain so the graph keeps pulling
  let watchdog = null;
  let framesSeen = 0;
  let gated = false;
  const detach = [];      // listeners to remove on release

  // Speech finding.
  let floor = 0.004;
  let speech = [];
  let preroll = [];
  let inSpeech = false;
  let loudFrames = 0;
  let quietMs = 0;
  let speechMs = 0;

  function now() {
    return Math.round(performance.now());
  }

  function emit(event) {
    if (typeof onEvent !== 'function') return;
    try { onEvent(JSON.stringify(Object.assign({ t: now() }, event))); } catch (e) { /* never throw into audio */ }
  }

  function setPhase(next, extra) {
    phase = next;
    emit(Object.assign({ type: 'phase', phase: next, gen }, extra || {}));
  }

  function resetSpeech() {
    floor = 0.004;
    speech = [];
    preroll = [];
    inSpeech = false;
    loudFrames = 0;
    quietMs = 0;
    speechMs = 0;
  }

  function listen(target, name, fn) {
    if (!target || typeof target.addEventListener !== 'function') return;
    target.addEventListener(name, fn);
    detach.push(() => { try { target.removeEventListener(name, fn); } catch (e) {} });
  }

  // Releases every audio resource. Safe to call many times.
  function release() {
    if (watchdog) { clearTimeout(watchdog); watchdog = null; }
    while (detach.length) detach.pop()();
    try { if (node && node.port) node.port.onmessage = null; } catch (e) {}
    try { if (node) node.onaudioprocess = null; } catch (e) {}
    try { node && node.disconnect(); } catch (e) {}
    try { source && source.disconnect(); } catch (e) {}
    try { sink && sink.disconnect(); } catch (e) {}
    try { stream && stream.getTracks().forEach((t) => t.stop()); } catch (e) {}
    try { context && context.state !== 'closed' && context.close(); } catch (e) {}
    stream = track = context = source = node = sink = null;
    framesSeen = 0;
    gated = false;
    resetSpeech();
  }

  function stopTracks(s) {
    try { s && s.getTracks().forEach((t) => t.stop()); } catch (e) {}
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

  function wav(samples) {
    const bytes = new Uint8Array(44 + samples.length * 2);
    const view = new DataView(bytes.buffer);
    const text = (at, s) => { for (let i = 0; i < s.length; i++) bytes[at + i] = s.charCodeAt(i); };
    text(0, 'RIFF'); view.setUint32(4, 36 + samples.length * 2, true); text(8, 'WAVE');
    text(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
    view.setUint32(24, RATE, true); view.setUint32(28, RATE * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true);
    text(36, 'data'); view.setUint32(40, samples.length * 2, true);
    for (let i = 0; i < samples.length; i++) {
      const v = Math.max(-1, Math.min(1, samples[i]));
      view.setInt16(44 + i * 2, v < 0 ? v * 0x8000 : v * 0x7fff, true);
    }
    return bytes;
  }

  function frame(raw, myGen) {
    if (myGen !== gen || !context) return;
    framesSeen++;
    if (phase === 'starting' && framesSeen >= 2 && track && track.readyState === 'live' && !track.muted) {
      if (watchdog) { clearTimeout(watchdog); watchdog = null; }
      setPhase('ready', { sampleRate: context.sampleRate, worklet: !!(node && node.port) });
    }
    if (phase !== 'ready' || gated) return;
    const f = resample(raw, context.sampleRate);
    const ms = (f.length / RATE) * 1000;
    const level = rms(f);
    emit({ type: 'level', gen, level: Math.min(10, level * 120) });
    const loud = level > Math.max(floor * 2.6, 0.011);
    if (!inSpeech) {
      floor = floor * 0.95 + Math.min(level, 0.05) * 0.05;
      preroll.push(f);
      if (preroll.length > PREROLL_FRAMES) preroll.shift();
      loudFrames = loud ? loudFrames + 1 : 0;
      if (loudFrames >= 2) {
        inSpeech = true;
        speech = preroll.slice();
        preroll = [];
        quietMs = 0;
        speechMs = 0;
        emit({ type: 'speech', gen, on: true });
      }
      return;
    }
    speech.push(f);
    speechMs += ms;
    quietMs = loud ? 0 : quietMs + ms;
    if (quietMs > END_SILENCE_MS || speechMs > MAX_SPEECH_MS) finish(myGen);
  }

  function finish(myGen) {
    const parts = speech;
    const spoken = speechMs - quietMs;
    speech = [];
    inSpeech = false;
    loudFrames = 0;
    emit({ type: 'speech', gen: myGen, on: false });
    if (spoken < MIN_SPEECH_MS) return; // a knock or a cough
    let length = 0;
    for (const p of parts) length += p.length;
    const all = new Float32Array(length);
    let at = 0;
    for (const p of parts) { all.set(p, at); at += p.length; }
    const seconds = all.length / RATE;
    if (typeof onSegment === 'function' && myGen === gen && phase === 'ready' && !gated) {
      try { onSegment(myGen, wav(all), seconds); } catch (e) {}
    }
  }

  // Stops capture because the platform took the audio away.
  function interrupt(reason, myGen) {
    if (myGen !== gen || phase === 'interrupted' || phase === 'stopped' || phase === 'idle') return;
    release();
    setPhase('interrupted', { reason });
  }

  function capabilities() {
    const nav = navigator;
    const md = nav.mediaDevices;
    let policy = null;
    try {
      const fp = document.permissionsPolicy || document.featurePolicy;
      if (fp && typeof fp.allowsFeature === 'function') policy = fp.allowsFeature('microphone');
    } catch (e) {}
    const Ctx = window.AudioContext || window.webkitAudioContext;
    return {
      secure: !!window.isSecureContext,
      topLevel: window.top === window.self,
      mediaDevices: !!(md && md.getUserMedia),
      audioContext: !!Ctx,
      audioWorklet: !!(Ctx && 'audioWorklet' in Ctx.prototype),
      audioSession: !!(nav.audioSession),
      audioSessionState: !!(nav.audioSession && 'state' in nav.audioSession),
      permissionsPolicy: policy,
      standalone: !!(nav.standalone || (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)),
      visible: document.visibilityState === 'visible',
    };
  }

  function interruptionActive() {
    if (document.visibilityState !== 'visible') return 'hidden';
    const s = navigator.audioSession;
    if (s && s.state === 'interrupted') return 'audio-session';
    return null;
  }

  async function buildGraph(myGen) {
    source = context.createMediaStreamSource(stream);
    sink = context.createGain();
    sink.gain.value = 0;
    sink.connect(context.destination);
    let usedWorklet = false;
    if (context.audioWorklet && typeof AudioWorkletNode === 'function') {
      try {
        const url = URL.createObjectURL(new Blob([WORKLET], { type: 'text/javascript' }));
        try { await context.audioWorklet.addModule(url); } finally { URL.revokeObjectURL(url); }
        if (myGen !== gen || !context) return;
        node = new AudioWorkletNode(context, 'vimo-tap', { numberOfInputs: 1, numberOfOutputs: 1, channelCount: 1 });
        // 128-sample blocks: batch to ~1024 for the speech finder.
        let acc = [];
        let count = 0;
        node.port.onmessage = (e) => {
          acc.push(e.data);
          count += e.data.length;
          if (count >= 1024) {
            const joined = new Float32Array(count);
            let at = 0;
            for (const p of acc) { joined.set(p, at); at += p.length; }
            acc = [];
            count = 0;
            frame(joined, myGen);
          }
        };
        usedWorklet = true;
      } catch (e) {
        emit({ type: 'diag', gen: myGen, step: 'worklet-fallback', error: String(e && e.name || e) });
        node = null;
      }
    }
    if (!usedWorklet) {
      if (myGen !== gen || !context) return;
      node = context.createScriptProcessor(1024, 1, 1);
      node.onaudioprocess = (e) => frame(e.inputBuffer.getChannelData(0), myGen);
    }
    source.connect(node);
    node.connect(sink);
  }

  function watch(myGen) {
    listen(track, 'mute', () => interrupt('track-muted', myGen));
    listen(track, 'ended', () => interrupt('track-ended', myGen));
    listen(context, 'statechange', () => {
      const s = context && context.state;
      if (s === 'interrupted' || s === 'closed' || (s === 'suspended' && phase === 'ready')) {
        interrupt('context-' + s, myGen);
      }
    });
    const session = navigator.audioSession;
    if (session && 'state' in session) {
      listen(session, 'statechange', () => {
        if (session.state === 'interrupted' || session.state === 'inactive') interrupt('audio-session-' + session.state, myGen);
      });
    }
    listen(document, 'visibilitychange', () => {
      if (document.visibilityState !== 'visible') interrupt('hidden', myGen);
    });
    listen(window, 'pagehide', () => interrupt('pagehide', myGen));
    listen(document, 'freeze', () => interrupt('freeze', myGen));
    if (navigator.mediaDevices) listen(navigator.mediaDevices, 'devicechange', () => interrupt('route-change', myGen));
  }

  function errorCode(e) {
    const name = e && e.name ? e.name : '';
    if (name === 'NotAllowedError' || name === 'SecurityError') return 'not-allowed';
    if (name === 'NotFoundError' || name === 'OverconstrainedError') return 'no-microphone';
    if (name === 'NotReadableError' || name === 'AbortError') return 'audio-busy';
    return 'audio-capture';
  }

  async function permissionState() {
    try {
      const r = await navigator.permissions.query({ name: 'microphone' });
      return r.state;
    } catch (e) {
      return null;
    }
  }

  // Must be called synchronously from a user tap. Resolves 'ready' or
  // rejects with an Error whose message is a short code.
  function start(myGen, events, segments) {
    if (typeof myGen !== 'number' || myGen <= gen) {
      return Promise.reject(new Error('stale-generation'));
    }
    // A new start replaces any older capture completely.
    release();
    gen = myGen;
    onEvent = events;
    onSegment = segments;
    const caps = capabilities();
    emit({ type: 'diag', gen: myGen, step: 'start', caps });
    if (!caps.secure) { setPhase('error', { code: 'insecure' }); return Promise.reject(new Error('insecure')); }
    if (!caps.mediaDevices || !caps.audioContext) { setPhase('error', { code: 'unsupported' }); return Promise.reject(new Error('unsupported')); }
    if (caps.permissionsPolicy === false) { setPhase('error', { code: 'policy-blocked' }); return Promise.reject(new Error('policy-blocked')); }
    const active = interruptionActive();
    if (active) { setPhase('interrupted', { reason: active }); return Promise.reject(new Error('interruption-active')); }

    // Inside the gesture: create and unlock the audio context first.
    const Ctx = window.AudioContext || window.webkitAudioContext;
    try { context = new Ctx(); } catch (e) { setPhase('error', { code: 'audio-context' }); return Promise.reject(new Error('audio-context')); }
    try { const r = context.resume(); if (r && r.catch) r.catch(() => {}); } catch (e) {}
    try { if (navigator.audioSession) navigator.audioSession.type = 'play-and-record'; } catch (e) {}
    setPhase('starting');

    const constraints = { audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true } };
    let request;
    try { request = navigator.mediaDevices.getUserMedia(constraints); } catch (e) { request = Promise.reject(e); }
    emit({ type: 'diag', gen: myGen, step: 'getUserMedia-requested' });

    return request.then(async (s) => {
      if (myGen !== gen || phase !== 'starting') {
        // Cancelled while the permission prompt was open.
        stopTracks(s);
        emit({ type: 'diag', gen: myGen, step: 'late-stream-stopped' });
        throw new Error('cancelled');
      }
      stream = s;
      track = s.getAudioTracks()[0] || null;
      emit({ type: 'diag', gen: myGen, step: 'stream', live: !!(track && track.readyState === 'live'), muted: !!(track && track.muted) });
      if (!track || track.readyState !== 'live') { release(); setPhase('error', { code: 'no-track' }); throw new Error('no-track'); }
      watch(myGen);
      if (context.state !== 'running') {
        try { await context.resume(); } catch (e) {}
      }
      if (myGen !== gen) throw new Error('cancelled');
      if (context.state !== 'running') {
        // Safari wants one more tap. Keep the stream; resumeAudio() finishes.
        emit({ type: 'diag', gen: myGen, step: 'context-' + context.state });
        setPhase('needs-gesture');
        throw new Error('needs-gesture');
      }
      await buildGraph(myGen);
      if (myGen !== gen) throw new Error('cancelled');
      return await armWatchdog(myGen);
    }, async (e) => {
      if (myGen !== gen) throw new Error('cancelled');
      const code = errorCode(e);
      const state = code === 'not-allowed' ? await permissionState() : null;
      release();
      setPhase('error', { code, permission: state });
      throw new Error(code + (state === 'denied' ? ':blocked' : ''));
    });
  }

  function armWatchdog(myGen) {
    return new Promise((resolve, reject) => {
      if (phase === 'ready') { resolve('ready'); return; }
      const check = () => {
        if (myGen !== gen) { reject(new Error('cancelled')); return; }
        if (phase === 'ready') { resolve('ready'); return; }
        if (phase !== 'starting') { reject(new Error(phase)); return; }
        setTimeout(check, 40);
      };
      watchdog = setTimeout(() => {
        watchdog = null;
        if (myGen !== gen || phase !== 'starting') return;
        const muted = !!(track && track.muted);
        release();
        setPhase('error', { code: muted ? 'muted' : 'no-frames', frames: framesSeen });
      }, WATCHDOG_MS);
      check();
    });
  }

  // The second tap Safari sometimes needs after the permission prompt.
  function resumeAudio(myGen) {
    if (myGen !== gen || phase !== 'needs-gesture' || !context) return Promise.reject(new Error('stale-generation'));
    let r;
    try { r = context.resume(); } catch (e) { r = Promise.reject(e); }
    setPhase('starting');
    return Promise.resolve(r).catch(() => {}).then(async () => {
      if (myGen !== gen) throw new Error('cancelled');
      if (!context || context.state !== 'running') { release(); setPhase('error', { code: 'audio-suspended' }); throw new Error('audio-suspended'); }
      await buildGraph(myGen);
      return await armWatchdog(myGen);
    });
  }

  window.vimoMic = {
    capabilities() { return JSON.stringify(capabilities()); },
    phase() { return phase; },
    generation() { return gen; },
    start,
    resumeAudio,
    // While VIMO speaks: drop input and forget any half-heard sentence.
    gate(myGen, on) {
      if (myGen !== gen) return;
      gated = !!on;
      resetSpeech();
      emit({ type: 'gate', gen: myGen, on: gated });
    },
    stop(myGen, reason) {
      if (myGen !== gen && myGen !== -1) return;
      const was = phase;
      release();
      if (was !== 'idle') setPhase('stopped', { reason: reason || 'stop' });
    },
    // Test hook: what is still held (must be all false after stop).
    held() {
      return JSON.stringify({ stream: !!stream, context: !!context, node: !!node, buffered: speech.length + preroll.length });
    },
  };

  // Legacy: VIMO once kept downloaded speech models in this browser. They are
  // no longer used or written. This removes them only when the owner asks.
  window.vimoLegacyModels = {
    async list() {
      try {
        const names = await caches.keys();
        return JSON.stringify(names.filter((n) => n === 'vimo-ear-v1' || n === 'transformers-cache'));
      } catch (e) {
        return '[]';
      }
    },
    async remove() {
      let removed = 0;
      try {
        for (const n of ['vimo-ear-v1', 'transformers-cache']) if (await caches.delete(n)) removed++;
      } catch (e) {}
      return removed;
    },
  };
})();
