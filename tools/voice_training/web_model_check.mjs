// Runs a built model exactly as the phone's browser will (transformers.js,
// 8-bit ONNX) over the owner's recordings and writes what it heard.
//   node web_model_check.mjs <models dir> <model name> <recordings dir> <out.jsonl>
// <model name> may also be a Hugging Face id (a ready-made baseline).
import fs from 'node:fs';
import path from 'node:path';
import { pipeline, env } from '@huggingface/transformers';

const [modelsDir, name, recDir, outPath] = process.argv.slice(2);
env.localModelPath = modelsDir;
env.allowLocalModels = true;
const asr = await pipeline('automatic-speech-recognition', name, { dtype: 'q8', device: 'cpu' });

function readWav(file) {
  const buf = fs.readFileSync(file);
  let offset = 12;
  while (offset < buf.length - 8) {
    const id = buf.toString('ascii', offset, offset + 4);
    const size = buf.readUInt32LE(offset + 4);
    if (id === 'data') {
      const pcm = new Int16Array(buf.buffer.slice(buf.byteOffset + offset + 8, buf.byteOffset + offset + 8 + size));
      return Float32Array.from(pcm, (v) => v / 32768);
    }
    offset += 8 + size;
  }
  throw new Error('no data chunk');
}

const out = fs.createWriteStream(outPath);
let n = 0;
const started = Date.now();
for (const lang of fs.readdirSync(recDir)) {
  const folder = path.join(recDir, lang);
  if (!fs.statSync(folder).isDirectory()) continue;
  for (const f of fs.readdirSync(folder).filter((f) => f.endsWith('.json')).sort()) {
    const meta = JSON.parse(fs.readFileSync(path.join(folder, f), 'utf8'));
    const audio = readWav(path.join(folder, f.replace(/\.json$/, '.wav')));
    const result = await asr(audio, { language: meta.language === 'en' ? 'english' : 'tamil', task: 'transcribe' });
    out.write(JSON.stringify({ id: meta.id, lang: meta.language, ref: meta.transcript, asr: result.text.trim() }) + '\n');
    n++;
  }
}
out.end();
// Counts only: the repository's logs are public.
console.log(`${name}: heard ${n} recordings in ${Math.round((Date.now() - started) / 1000)} s`);
