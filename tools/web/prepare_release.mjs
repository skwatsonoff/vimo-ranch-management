import { createHash } from 'node:crypto';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const build = 'build/web';
const sdkPath = process.argv[2];
if (!sdkPath) throw new Error('Pass the installed Firebase npm package directory.');
const { version } = JSON.parse(await readFile(join(sdkPath, 'package.json'), 'utf8'));
const html = await readFile(join(build, 'index.html'), 'utf8');
if (!html.includes(`flutterfire_web_sdk_version = "${version}"`)) {
  throw new Error('Firebase npm and web SDK versions must match.');
}

const modules = {
  core: 'firebase-app.js',
  auth: 'firebase-auth.js',
  firestore: 'firebase-firestore-pipelines.js',
  messaging: 'firebase-messaging.js',
};
await mkdir(join(build, 'firebase-sdk'), { recursive: true });
for (const name of Object.values(modules)) {
  const source = await readFile(join(sdkPath, name), 'utf8');
  await writeFile(join(build, 'firebase-sdk', name),
    source.replaceAll(`https://www.gstatic.com/firebasejs/${version}/`, './'));
}
await writeFile(join(build, 'firebase-sdk.js'), `
  const core = await import('./firebase-sdk/${modules.core}');
  const [auth, firestore, messaging] = await Promise.all([
    import('./firebase-sdk/${modules.auth}'),
    import('./firebase-sdk/${modules.firestore}'),
    import('./firebase-sdk/${modules.messaging}'),
  ]);
  Object.assign(window, {
    firebase_core: core, firebase_auth: auth,
    firebase_firestore: firestore, firebase_messaging: messaging,
  });
`);

async function list(dir) {
  const entries = await readdir(join(build, dir), { withFileTypes: true });
  return (await Promise.all(entries.map(entry => {
    const path = `${dir}/${entry.name}`;
    return entry.isDirectory() ? list(path) : path;
  }))).flat();
}

const paths = [
  'index.html', 'flutter_bootstrap.js', 'main.dart.js', 'manifest.json',
  'version.json', 'apple-touch-icon.png', 'favicon.png',
  'vimo_ear.js', 'firebase-sdk.js',
  ...(await list('firebase-sdk')),
  ...(await list('assets')).filter(path => !path.endsWith('/NOTICES')),
  ...(await list('icons')),
  ...(await list('canvaskit')).filter(path => /\/canvaskit\.(js|wasm)$/.test(path)),
].sort();
const digest = createHash('sha256');
for (const path of paths) digest.update(await readFile(join(build, path)));
await writeFile(join(build, 'vimo-shell.js'),
  `self.vimoShell = ${JSON.stringify({ version: digest.digest('hex').slice(0, 16), paths })};\n`);
