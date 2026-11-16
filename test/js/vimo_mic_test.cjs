// Browser checks for web/vimo_mic.js in real Chromium with a fake microphone.
// Run: node test/js/vimo_mic_test.cjs   (uses the pre-installed Playwright)
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require('playwright');

const script = fs.readFileSync(path.join(__dirname, '../../web/vimo_mic.js'), 'utf8');
const page = `<!doctype html><meta charset="utf-8"><body><script>${script}</script>
<script>
  window.log = [];
  window.segments = [];
  window.ev = (j) => window.log.push(JSON.parse(j));
  window.seg = (g, wav, s) => window.segments.push({ g, n: wav.length, head: String.fromCharCode(...wav.slice(0, 4)), s });
  window.phases = () => window.log.filter((e) => e.type === 'phase').map((e) => e.gen + ':' + e.phase + (e.reason ? '/' + e.reason : '') + (e.code ? '/' + e.code : ''));
  window.go = (g) => vimoMic.start(g, ev, seg).then((r) => r, (e) => 'ERR:' + e.message);
</script>`;

function syntheticWav() {
  const rate = 16000;
  const n = rate * 3;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8); buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22); buf.writeUInt32LE(rate, 24);
  buf.writeUInt32LE(rate * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) {
    const t = i / rate;
    const voiced = t < 1.2 ? 0.35 * (Math.sin(2 * Math.PI * 180 * t) + 0.5 * Math.sin(2 * Math.PI * 360 * t)) * (0.6 + 0.4 * Math.sin(2 * Math.PI * 4 * t)) : 0;
    buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, voiced)) * 32000), 44 + i * 2);
  }
  return buf;
}

const results = [];
async function check(name, fn) {
  try {
    await fn();
    results.push(['PASS', name]);
  } catch (e) {
    results.push(['FAIL', name, e.message]);
  }
}

(async () => {
  const server = http.createServer((_, res) => { res.setHeader('content-type', 'text/html'); res.end(page); });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const url = `http://localhost:${server.address().port}/`;
  // A synthetic "utterance": 1.2 s of voiced tone, then 1.8 s of quiet.
  const os = require('node:os');
  const wavPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'vimo-mic-')), 'utterance.wav');
  fs.writeFileSync(wavPath, syntheticWav());
  const browser = await chromium.launch({
    args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
      `--use-file-for-fake-audio-capture=${wavPath}`, '--autoplay-policy=no-user-gesture-required'],
  });
  const ctx = await browser.newContext({ permissions: ['microphone'] });
  const fresh = async (init) => {
    const p = await ctx.newPage();
    if (init) await p.addInitScript(init);
    await p.goto(url);
    return p;
  };

  await check('capabilities report a secure, top-level page with AudioWorklet', async () => {
    const p = await fresh();
    const caps = JSON.parse(await p.evaluate(() => vimoMic.capabilities()));
    assert.equal(caps.secure, true);
    assert.equal(caps.topLevel, true);
    assert.equal(caps.mediaDevices, true);
    assert.equal(caps.audioWorklet, true);
    await p.close();
  });

  await check('first tap: ready only after real frames, then a WAV sentence arrives', async () => {
    const p = await fresh();
    const r = await p.evaluate(() => go(1));
    assert.equal(r, 'ready');
    const phases = await p.evaluate(() => phases());
    assert.deepEqual(phases, ['1:starting', '1:ready']);
    const diag = await p.evaluate(() => log.filter((e) => e.type === 'diag').map((e) => e.step));
    assert.ok(diag.includes('getUserMedia-requested') && diag.includes('stream'), diag.join(','));
    // The fake device beeps: speech finder should cut at least one sentence.
    await p.waitForFunction(() => segments.length > 0, null, { timeout: 8000 });
    const s = await p.evaluate(() => segments[0]);
    assert.equal(s.head, 'RIFF');
    assert.equal(s.g, 1);
    await p.evaluate(() => vimoMic.stop(1, 'test'));
    assert.deepEqual(JSON.parse(await p.evaluate(() => vimoMic.held())), { stream: false, context: false, node: false, buffered: 0 });
    await p.close();
  });

  await check('ScriptProcessor fallback works when AudioWorklet is missing', async () => {
    const p = await fresh(() => { delete AudioContext.prototype.audioWorklet; Object.defineProperty(AudioContext.prototype, 'audioWorklet', { get: () => undefined }); });
    assert.equal(await p.evaluate(() => go(1)), 'ready');
    const ready = await p.evaluate(() => log.find((e) => e.phase === 'ready'));
    assert.equal(ready.worklet, false);
    await p.close();
  });

  await check('double tap: the older start is cancelled, one stream is held', async () => {
    const p = await fresh(() => {
      const real = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
      window.tracks = [];
      navigator.mediaDevices.getUserMedia = async (c) => { const s = await real(c); window.tracks.push(s.getAudioTracks()[0]); return s; };
    });
    const [a, b] = await p.evaluate(() => Promise.all([go(1), go(2)]));
    assert.equal(a, 'ERR:cancelled');
    assert.equal(b, 'ready');
    const states = await p.evaluate(() => tracks.map((t) => t.readyState));
    assert.deepEqual(states.sort(), ['ended', 'live']);
    assert.equal(await p.evaluate(() => go(2)), 'ERR:stale-generation');
    await p.close();
  });

  await check('a stream that arrives after Stop is stopped at once', async () => {
    const p = await fresh(() => {
      const real = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
      navigator.mediaDevices.getUserMedia = async (c) => { const s = await real(c); window.late = s.getAudioTracks()[0]; await new Promise((r) => setTimeout(r, 400)); return s; };
    });
    const r = await p.evaluate(async () => { const pr = go(1); setTimeout(() => vimoMic.stop(1, 'user'), 50); return pr; });
    assert.equal(r, 'ERR:cancelled');
    assert.equal(await p.evaluate(() => late.readyState), 'ended');
    const diag = await p.evaluate(() => log.filter((e) => e.step === 'late-stream-stopped').length);
    assert.equal(diag, 1);
    await p.close();
  });

  await check('permission refused: error not-allowed, nothing held', async () => {
    const p = await fresh(() => { navigator.mediaDevices.getUserMedia = () => Promise.reject(new DOMException('no', 'NotAllowedError')); });
    assert.match(await p.evaluate(() => go(1)), /^ERR:not-allowed/);
    assert.deepEqual(await p.evaluate(() => phases()), ['1:starting', '1:error/not-allowed']);
    assert.equal(JSON.parse(await p.evaluate(() => vimoMic.held())).stream, false);
    await p.close();
  });

  await check('microphone busy maps to audio-busy', async () => {
    const p = await fresh(() => { navigator.mediaDevices.getUserMedia = () => Promise.reject(new DOMException('busy', 'NotReadableError')); });
    assert.equal(await p.evaluate(() => go(1)), 'ERR:audio-busy');
    await p.close();
  });

  await check('allowed but muted track: watchdog reports, never "ready"', async () => {
    const p = await fresh(() => {
      const real = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
      navigator.mediaDevices.getUserMedia = async (c) => { const s = await real(c); Object.defineProperty(s.getAudioTracks()[0], 'muted', { get: () => true }); return s; };
    });
    const r = await p.evaluate(() => go(1));
    assert.equal(r, 'ERR:error');
    const phases = await p.evaluate(() => phases());
    assert.deepEqual(phases, ['1:starting', '1:error/muted']);
    assert.equal(JSON.parse(await p.evaluate(() => vimoMic.held())).stream, false);
    await p.close();
  });

  await check('page hidden while listening: interrupted, released, no auto restart', async () => {
    const p = await fresh();
    assert.equal(await p.evaluate(() => go(1)), 'ready');
    await p.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' }); document.dispatchEvent(new Event('visibilitychange')); });
    assert.deepEqual((await p.evaluate(() => phases())).slice(-1), ['1:interrupted/hidden']);
    assert.deepEqual(JSON.parse(await p.evaluate(() => vimoMic.held())), { stream: false, context: false, node: false, buffered: 0 });
    // Still hidden: a new start is refused.
    assert.equal(await p.evaluate(() => go(2)), 'ERR:interruption-active');
    const n = await p.evaluate(() => segments.length);
    await p.waitForTimeout(1200);
    assert.equal(await p.evaluate(() => segments.length), n, 'no audio after interruption');
    await p.close();
  });

  await check('audio session interrupted (call or another app): interrupted', async () => {
    const p = await fresh(() => {
      const s = new EventTarget();
      s.state = 'active';
      s.type = 'auto';
      Object.defineProperty(navigator, 'audioSession', { get: () => s });
    });
    assert.equal(await p.evaluate(() => go(1)), 'ready');
    await p.evaluate(() => { navigator.audioSession.state = 'interrupted'; navigator.audioSession.dispatchEvent(new Event('statechange')); });
    assert.deepEqual((await p.evaluate(() => phases())).slice(-1), ['1:interrupted/audio-session-interrupted']);
    assert.equal(await p.evaluate(() => go(2)), 'ERR:interruption-active');
    await p.evaluate(() => { navigator.audioSession.state = 'active'; });
    assert.equal(await p.evaluate(() => go(3)), 'ready', 'explicit Resume after the interruption ends');
    await p.close();
  });

  await check('track ended or muted mid-capture: interrupted', async () => {
    const p = await fresh(() => {
      const real = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
      navigator.mediaDevices.getUserMedia = async (c) => { const s = await real(c); window.t = s.getAudioTracks()[0]; return s; };
    });
    assert.equal(await p.evaluate(() => go(1)), 'ready');
    await p.evaluate(() => t.dispatchEvent(new Event('mute')));
    assert.deepEqual((await p.evaluate(() => phases())).slice(-1), ['1:interrupted/track-muted']);
    assert.equal(await p.evaluate(() => go(2)), 'ready');
    await p.evaluate(() => t.dispatchEvent(new Event('ended')));
    assert.deepEqual((await p.evaluate(() => phases())).slice(-1), ['2:interrupted/track-ended']);
    await p.close();
  });

  await check('input route change (Bluetooth) interrupts', async () => {
    const p = await fresh();
    assert.equal(await p.evaluate(() => go(1)), 'ready');
    await p.evaluate(() => navigator.mediaDevices.dispatchEvent(new Event('devicechange')));
    assert.deepEqual((await p.evaluate(() => phases())).slice(-1), ['1:interrupted/route-change']);
    await p.close();
  });

  await check('gate while VIMO speaks: no sentences', async () => {
    const p = await fresh();
    assert.equal(await p.evaluate(() => go(1)), 'ready');
    await p.evaluate(() => vimoMic.gate(1, true));
    await p.evaluate(() => { segments.length = 0; });
    await p.waitForTimeout(2500);
    assert.equal(await p.evaluate(() => segments.length), 0);
    await p.evaluate(() => vimoMic.gate(1, false));
    await p.waitForFunction(() => segments.length > 0, null, { timeout: 8000 });
    await p.close();
  });

  await check('suspended audio context asks for one more tap, resumeAudio finishes', async () => {
    const p = await fresh(() => {
      // Simulate Safari: resume() does nothing until a second call.
      const realResume = AudioContext.prototype.resume;
      let calls = 0;
      AudioContext.prototype.resume = function () { calls++; if (calls < 3) return Promise.resolve(); return realResume.call(this); };
      const RealCtx = AudioContext;
      window.AudioContext = function () { const c = new RealCtx(); c.suspend(); return c; };
      window.AudioContext.prototype = RealCtx.prototype;
    });
    assert.equal(await p.evaluate(() => go(1)), 'ERR:needs-gesture');
    assert.equal(await p.evaluate(() => vimoMic.phase()), 'needs-gesture');
    assert.equal(await p.evaluate(() => vimoMic.resumeAudio(1).then((r) => r, (e) => 'ERR:' + e.message)), 'ready');
    await p.close();
  });

  await check('insecure or policy-blocked pages refuse before touching the mic', async () => {
    const p = await fresh(() => {
      document.permissionsPolicy = { allowsFeature: () => false };
      window.calls = 0;
      const real = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
      navigator.mediaDevices.getUserMedia = (c) => { window.calls++; return real(c); };
    });
    assert.equal(await p.evaluate(() => go(1)), 'ERR:policy-blocked');
    assert.equal(await p.evaluate(() => calls), 0);
    await p.close();
  });

  await check('no model or audio is persisted in browser storage', async () => {
    const p = await fresh();
    assert.equal(await p.evaluate(() => go(1)), 'ready');
    await p.waitForFunction(() => segments.length > 0, null, { timeout: 8000 });
    await p.evaluate(() => vimoMic.stop(1));
    const stored = await p.evaluate(async () => ({
      caches: await caches.keys(),
      local: localStorage.length,
      session: sessionStorage.length,
      idb: indexedDB.databases ? (await indexedDB.databases()).length : 0,
    }));
    assert.deepEqual(stored, { caches: [], local: 0, session: 0, idb: 0 });
    await p.close();
  });

  await check('legacy model caches are listed and removed only on request', async () => {
    const p = await fresh();
    await p.evaluate(async () => { await (await caches.open('vimo-ear-v1')).put('/x', new Response('m')); await caches.open('vimo-shell-1'); });
    assert.deepEqual(JSON.parse(await p.evaluate(() => vimoLegacyModels.list())), ['vimo-ear-v1']);
    assert.equal(await p.evaluate(() => vimoLegacyModels.remove()), 1);
    assert.deepEqual(await p.evaluate(() => caches.keys()), ['vimo-shell-1']);
    await p.close();
  });

  await browser.close();
  server.close();
  for (const r of results) console.log(r.join(' | '));
  const failed = results.filter((r) => r[0] === 'FAIL').length;
  console.log(`vimo_mic: ${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
