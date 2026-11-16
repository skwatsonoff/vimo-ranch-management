// Real interop check: Dart (compiled to JS) <-> web/vimo_mic.js in Chromium.
// Run: node test/js/capture_interop_test.cjs  (needs `dart` on PATH)
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { chromium } = require('playwright');

const root = path.join(__dirname, '../..');
const out = fs.mkdtempSync(path.join(os.tmpdir(), 'vimo-probe-'));
execFileSync('dart', ['compile', 'js', '-O1', '-o', path.join(out, 'probe.js'), path.join(__dirname, 'capture_probe.dart')], { cwd: root, stdio: 'pipe' });
const mic = fs.readFileSync(path.join(root, 'web/vimo_mic.js'), 'utf8');
const probe = fs.readFileSync(path.join(out, 'probe.js'), 'utf8');
const page = `<!doctype html><meta charset="utf-8"><script>window.lines=[];window.probeLog=(l)=>lines.push(l);</script><script>${mic}</script><script>${probe}</script>`;

function utteranceWav() {
  const rate = 16000, n = rate * 3, buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8); buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22); buf.writeUInt32LE(rate, 24);
  buf.writeUInt32LE(rate * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) { const t = i / rate; const v = t < 1.2 ? 0.35 * Math.sin(2 * Math.PI * 180 * t) * (0.6 + 0.4 * Math.sin(8 * Math.PI * t)) : 0; buf.writeInt16LE(Math.round(v * 32000), 44 + i * 2); }
  return buf;
}

(async () => {
  const wavPath = path.join(out, 'u.wav');
  fs.writeFileSync(wavPath, utteranceWav());
  const server = http.createServer((_, res) => { res.setHeader('content-type', 'text/html'); res.end(page); });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const browser = await chromium.launch({ args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-audio-capture=${wavPath}`] });
  const ctx = await browser.newContext({ permissions: ['microphone'] });
  const results = [];
  const check = async (name, fn) => { try { await fn(); results.push(['PASS', name]); } catch (e) { results.push(['FAIL', name, e.message]); } };
  const p = await ctx.newPage();
  await p.goto(`http://localhost:${server.address().port}/`);
  await p.waitForFunction(() => lines.includes('supported:true'));

  await check('Dart tap -> JS getUserMedia -> ready -> listening', async () => {
    await p.evaluate(() => probeStart());
    await p.waitForFunction(() => lines.includes('phase:listening'), null, { timeout: 8000 });
    const l = await p.evaluate(() => lines);
    assert.ok(l.indexOf('phase:connecting') < l.indexOf('phase:listening'), l.join(' '));
  });
  await check('a real sentence crosses into Dart as WAV bytes and comes back as text', async () => {
    await p.waitForFunction(() => lines.some((l) => l.startsWith('text:heard RIFF')), null, { timeout: 10000 });
  });
  await check('JS interruption reaches Dart: interrupted with reason, mic released', async () => {
    await p.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' }); document.dispatchEvent(new Event('visibilitychange')); });
    await p.waitForFunction(() => lines.includes('phase:interrupted:hidden'), null, { timeout: 4000 });
    assert.deepEqual(JSON.parse(await p.evaluate(() => vimoMic.held())), { stream: false, context: false, node: false, buffered: 0 });
  });
  await check('start while still hidden is refused (interruption still observable)', async () => {
    await p.evaluate(() => probeStart());
    await p.waitForFunction(() => lines.filter((l) => l.startsWith('phase:interrupted')).length >= 2, null, { timeout: 4000 });
  });
  await check('resume after visible again: new generation listens', async () => {
    await p.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' }); });
    const before = await p.evaluate(() => lines.filter((l) => l === 'phase:listening').length);
    await p.evaluate(() => probeStart());
    await p.waitForFunction((n) => lines.filter((l) => l === 'phase:listening').length > n, before, { timeout: 8000 });
  });
  await check('lifecycle pause from Dart stops the JS capture', async () => {
    await p.evaluate(() => probeInterrupt());
    await p.waitForFunction(() => lines.includes('phase:interrupted:lifecycle-paused'), null, { timeout: 4000 });
    assert.equal(JSON.parse(await p.evaluate(() => vimoMic.held())).stream, false);
  });
  await check('permission refused maps to CaptureError.denied in Dart', async () => {
    const q = await ctx.newPage();
    await q.addInitScript(() => { navigator.mediaDevices.getUserMedia = () => Promise.reject(new DOMException('no', 'NotAllowedError')); });
    await q.goto(`http://localhost:${server.address().port}/`);
    await q.waitForFunction(() => lines.includes('supported:true'));
    await q.evaluate(() => probeStart());
    await q.waitForFunction(() => lines.some((l) => l.startsWith('phase:error')), null, { timeout: 4000 });
    assert.ok((await q.evaluate(() => lines)).includes('phase:error:denied'));
  });
  await browser.close();
  server.close();
  for (const r of results) console.log(r.join(' | '));
  const failed = results.filter((r) => r[0] === 'FAIL').length;
  console.log(`capture interop: ${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
