// Checks tools/voice_bridge/Code.gs (v2) with fake Google services.
// Run: node tools/voice_bridge/bridge_test.cjs
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const results = [];
function check(name, fn) {
  try { fn(); results.push(['PASS', name]); } catch (e) { results.push(['FAIL', name, e.message]); }
}

function makeWorld() {
  const w = {
    props: {
      FIREBASE_PROJECT_ID: 'my-ranch-sync',
      FIREBASE_WEB_API_KEY: 'public-web-key',
      VIMO_DRIVE_FOLDER_ID: 'root',
      GEMINI_ENABLED: 'true',
      GEMINI_PROJECT_ID: 'vimo-free-test',
      GEMINI_API_KEY: 'server-only-key',
    },
    billing: {billingEnabled: false},
    modelOk: true,
    geminiStatus: 200,
    geminiText: JSON.stringify({schema: 'vimo.milk.v2', intent: 'milk_record', uncertain: true,
      entries: [{cow: 'C1', litres: null, litresChoices: [5, 6], session: null}]}),
    member: {active: true, status: 'active', role: 'Editor'},
    users: {['good-token'.padEnd(120, 'x')]: 'uid-1', ['other-token'.padEnd(120, 'y')]: 'uid-2'},
    calls: [],
    geminiCalls: 0,
    geminiBodies: [],
    files: new Map(), // path -> {content, trashed}
  };
  const reply = (data, status = 200) => ({getResponseCode: () => status, getContentText: () => JSON.stringify(data)});
  function folderAt(p) {
    return {
      p,
      getId: () => p,
      getName: () => p.split('/').pop(),
      getFoldersByName(name) {
        const sub = p + '/' + name;
        const exists = [...w.files.keys()].some(k => k.startsWith(sub + '/')) || w.files.has(sub + '/');
        let used = false;
        return {hasNext: () => exists && !used, next: () => { used = true; return folderAt(sub); }};
      },
      createFolder(name) { w.files.set(p + '/' + name + '/', {dir: true}); return folderAt(p + '/' + name); },
      getFolders() {
        const names = new Set();
        for (const k of w.files.keys()) {
          if (!k.startsWith(p + '/')) continue;
          const rest = k.slice(p.length + 1);
          if (rest.includes('/')) names.add(rest.split('/')[0]);
        }
        const list = [...names].map(n => folderAt(p + '/' + n));
        return {hasNext: () => list.length > 0, next: () => list.shift()};
      },
      getFiles() {
        const list = [...w.files.entries()]
          .filter(([k, v]) => !v.dir && !v.trashed && k.startsWith(p + '/') && !k.slice(p.length + 1).includes('/'))
          .map(([k]) => fileAt(k));
        return {hasNext: () => list.length > 0, next: () => list.shift()};
      },
      getFilesByName(name) {
        const f = w.files.get(p + '/' + name);
        const ok = f && !f.trashed && !f.dir;
        let used = false;
        return {hasNext: () => ok && !used, next: () => { used = true; return fileAt(p + '/' + name); }};
      },
      createFile(nameOrBlob, content) {
        if (typeof nameOrBlob === 'string') w.files.set(p + '/' + nameOrBlob, {content});
        else w.files.set(p + '/' + nameOrBlob.name, {content: nameOrBlob.bytes});
      },
      setTrashed() { for (const k of w.files.keys()) if (k.startsWith(p + '/')) w.files.get(k).trashed = true; },
    };
  }
  function fileAt(k) {
    return {
      getName: () => k.split('/').pop(),
      getBlob: () => ({getDataAsString: () => w.files.get(k).content}),
      setContent: c => { w.files.get(k).content = c; },
      setTrashed: () => { w.files.get(k).trashed = true; },
    };
  }
  w.runtime = vm.createContext({
    PropertiesService: {getScriptProperties: () => ({
      getProperty: k => (k in w.props ? w.props[k] : null),
      setProperty: (k, v) => { w.props[k] = v; },
      deleteProperty: k => { delete w.props[k]; },
    })},
    ScriptApp: {getOAuthToken: () => 'script-token'},
    LockService: {getScriptLock: () => ({tryLock: () => true, releaseLock: () => {}})},
    ContentService: {MimeType: {JSON: 'json'}, createTextOutput: s => ({setMimeType: () => JSON.parse(s)})},
    DriveApp: {getFolderById: id => folderAt(id), createFolder: n => folderAt(n)},
    Utilities: {
      DigestAlgorithm: {SHA_256: 'sha256'},
      Charset: {UTF_8: 'utf8'},
      computeDigest: (_, text) => [...crypto.createHash('sha256').update(text, 'utf8').digest()].map(b => (b > 127 ? b - 256 : b)),
      formatDate: () => '2026-11-16',
      base64Decode: s => [...Buffer.from(s, 'base64')],
      newBlob: (bytes) => ({bytes, setName(n) { this.name = n; return this; }}),
    },
    UrlFetchApp: {fetch(url, options = {}) {
      w.calls.push(url);
      if (url.includes('identitytoolkit')) {
        const uid = w.users[JSON.parse(options.payload).idToken];
        return uid ? reply({users: [{localId: uid}]}) : reply({error: {message: 'INVALID_ID_TOKEN'}}, 400);
      }
      if (url.includes('firestore.googleapis.com')) {
        if (!w.member || !url.endsWith('/members/uid-1')) return reply({}, 403);
        return reply({fields: {
          active: {booleanValue: w.member.active}, status: {stringValue: w.member.status}, role: {stringValue: w.member.role}}});
      }
      if (url.includes('apikeys.googleapis.com')) return reply({parent: 'projects/123/locations/global', name: 'k'});
      if (url.includes('cloudresourcemanager')) return reply({projectId: 'vimo-free-test'});
      if (url.includes('cloudbilling')) return reply(w.billing);
      if (url.endsWith(':generateContent')) {
        w.geminiCalls++;
        w.geminiBodies.push(options.payload);
        return w.geminiStatus === 200
          ? reply({candidates: [{content: {parts: [{text: w.geminiText}]}}]})
          : reply({}, w.geminiStatus);
      }
      if (url.includes('generativelanguage.googleapis.com/v1beta/models/')) {
        return w.modelOk ? reply({supportedGenerationMethods: ['generateContent']}) : reply({}, 404);
      }
      throw Error('unexpected ' + url);
    }},
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'Code.gs'), 'utf8'), w.runtime);
  w.post = (over = {}) => w.runtime.doPost({postData: {contents: JSON.stringify({
    idToken: 'good-token'.padEnd(120, 'x'), ranchId: 'ranch_1', op: 'milk', geminiOptIn: true,
    request: {schema: 'vimo.milk.req.v2', text: 'C1 அஞ்சா ஆறா லிட்டர்', candidates: ['C1']}, ...over,
  })}});
  return w;
}

const example = (over = {}) => ({
  schema: 'vimo.example.v1', eventId: crypto.randomBytes(16).toString('hex'), lang: 'ta',
  text: 'செவ்வாள அஞ்சு லிட்டர்', cowId: 'cow_7', cowSpoken: 'செவ்வாள', litres: 5, session: 'Morning',
  intent: 'milk_record', label: 'confirmed', provenance: 'vimo', datasetVersion: 1, ...over,
});

check('old shared access code and missing tokens are refused with zero Gemini calls', () => {
  const w = makeWorld();
  assert.deepEqual(w.post({idToken: undefined, code: 'a'.repeat(64), scope: 'b'.repeat(64)}), {error: 'access'});
  assert.deepEqual(w.post({idToken: 'bad'.padEnd(120, 'z')}), {error: 'access'});
  assert.equal(w.geminiCalls, 0);
});

check('a valid token for a non-member, inactive member, or other ranch is refused', () => {
  let w = makeWorld();
  assert.deepEqual(w.post({idToken: 'other-token'.padEnd(120, 'y')}), {error: 'access'});
  w = makeWorld(); w.member.status = 'pending';
  assert.deepEqual(w.post(), {error: 'access'});
  w = makeWorld(); w.member.active = false;
  assert.deepEqual(w.post(), {error: 'access'});
  assert.equal(w.geminiCalls, 0);
});

check('membership is read with the caller token, so Firestore rules decide', () => {
  const w = makeWorld();
  w.post({op: 'status'});
  assert.ok(w.calls.some(u => u.includes('/documents/ranches/ranch_1/members/uid-1')));
});

check('happy path: tokenized request, validated v2 reply, no cow names sent', () => {
  const w = makeWorld();
  const r = w.post();
  assert.equal(r.ok, true);
  assert.deepEqual(r.reply.entries[0].litresChoices, [5, 6]);
  assert.equal(w.geminiCalls, 1);
  const sent = w.geminiBodies[0];
  assert.ok(sent.includes('C1') && !sent.includes('Kanmani') && !sent.includes('ranch_1') && !sent.includes('uid-1'));
  assert.ok(w.calls.some(u => u.endsWith('gemini-3.1-flash-lite:generateContent')));
});

check('kill switch, no opt-in, billing on, billing account, model gone: zero Gemini calls', () => {
  for (const [label, change, expected] of [
    ['switch off', w => { delete w.props.GEMINI_ENABLED; }, 'billing'],
    ['no opt-in', w => {}, 'consent'],
    ['billing enabled', w => { w.billing = {billingEnabled: true}; }, 'billing'],
    ['billing unknown', w => { w.billing = {}; }, 'billing'],
    ['billing account linked', w => { w.billing = {billingEnabled: false, billingAccountName: 'billingAccounts/1'}; }, 'billing'],
    ['model unavailable', w => { w.modelOk = false; }, 'billing'],
  ]) {
    const w = makeWorld();
    change(w);
    const r = w.post(label === 'no opt-in' ? {geminiOptIn: false} : {});
    assert.deepEqual(r, {error: expected}, label);
    assert.equal(w.geminiCalls, 0, label);
  }
});

check('unsanitized or off-schema requests are refused before Gemini', () => {
  for (const request of [
    {schema: 'vimo.milk.req.v1', text: 'x', candidates: []},
    {schema: 'vimo.milk.req.v2', text: 'Kanmani 98765 43210', candidates: []},
    {schema: 'vimo.milk.req.v2', text: 'see https://x.y', candidates: []},
    {schema: 'vimo.milk.req.v2', text: 'x'.repeat(161), candidates: []},
    {schema: 'vimo.milk.req.v2', text: 'C1 5', candidates: ['Kanmani']},
  ]) {
    const w = makeWorld();
    assert.deepEqual(w.post({request}), {error: 'input'});
    assert.equal(w.geminiCalls, 0);
  }
});

check('quota: reserved before calling; per-ranch and global limits; 429 never retried', () => {
  const w = makeWorld();
  w.props.GEMINI_RANCH_DAILY = '2';
  assert.equal(w.post().ok, true);
  assert.equal(w.post().ok, true);
  assert.deepEqual(w.post(), {error: 'quota'});
  assert.equal(w.geminiCalls, 2);
  const g = makeWorld();
  g.props.GEMINI_GLOBAL_DAILY = '0';
  assert.deepEqual(g.post(), {error: 'quota'});
  assert.equal(g.geminiCalls, 0);
  const q = makeWorld();
  q.geminiStatus = 429;
  assert.deepEqual(q.post(), {error: 'quota'});
  assert.equal(q.geminiCalls, 1);
});

check('malformed or unsafe model replies are dropped', () => {
  for (const text of [
    'not json',
    JSON.stringify({schema: 'vimo.milk.v2', intent: 'save', uncertain: false, entries: []}),
    JSON.stringify({schema: 'vimo.milk.v2', intent: 'milk_record', uncertain: false, entries: [{cow: 'C7'}]}),
    JSON.stringify({schema: 'vimo.milk.v2', intent: 'milk_record', uncertain: false, entries: [{cow: 'C1', litres: -5}]}),
    JSON.stringify({schema: 'vimo.milk.v2', intent: 'milk_record', uncertain: false, entries: [{cow: 'C1', litres: 500}]}),
    JSON.stringify({schema: 'vimo.milk.v2', intent: 'not_milk', uncertain: false, entries: [{cow: 'C1'}]}),
  ]) {
    const w = makeWorld();
    w.geminiText = text;
    assert.deepEqual(w.post(), {error: 'unavailable'}, text);
  }
});

check('learning needs consent; examples are immutable, deduplicated and ranch-scoped', () => {
  const w = makeWorld();
  const e = example();
  assert.deepEqual(w.post({op: 'example', example: e}), {error: 'consent'});
  assert.equal(w.post({op: 'consent', text: true, voice: false}).ok, true);
  assert.deepEqual(w.post({op: 'example', example: e}), {ok: true, duplicate: false});
  assert.deepEqual(w.post({op: 'example', example: e}), {ok: true, duplicate: true});
  assert.deepEqual(w.post({op: 'example', example: {...example(), litres: -1}}), {error: 'input'});
  assert.deepEqual(w.post({op: 'example', example: {...example(), label: 'guessed'}}), {error: 'input'});
  const paths = [...w.files.entries()].filter(([k, v]) => k.includes('/examples/') && !v.dir).map(([k]) => k);
  assert.equal(paths.length, 1);
  assert.ok(!paths[0].includes('ranch_1') && !paths[0].includes('uid-1'), 'opaque Drive names');
  assert.equal(w.geminiCalls, 0);
});

check('voice samples need their own consent', () => {
  const w = makeWorld();
  w.post({op: 'consent', text: true, voice: false});
  const wav = Buffer.alloc(44 + 3200); wav.write('RIFF', 0); wav.write('WAVE', 8);
  const sample = {op: 'sample', eventId: crypto.randomBytes(16).toString('hex'), wav: wav.toString('base64'), transcript: 'கண்மணி அஞ்சு'};
  assert.deepEqual(w.post(sample), {error: 'consent'});
  w.post({op: 'consent', text: true, voice: true});
  assert.deepEqual(w.post(sample), {ok: true, duplicate: false});
  assert.deepEqual(w.post(sample), {ok: true, duplicate: true});
});

check('alias learning: two confirmations, conflicts kept apart, manifest checksum', () => {
  const w = makeWorld();
  w.post({op: 'consent', text: true});
  w.post({op: 'example', example: example()});
  assert.deepEqual(w.post({op: 'lessons'}).aliases, []);
  w.post({op: 'example', example: example()});
  w.post({op: 'example', example: example({cowSpoken: 'லச்சு', cowId: 'cow_1'})});
  w.post({op: 'example', example: example({cowSpoken: 'லச்சு', cowId: 'cow_2'})});
  w.runtime.rebuildAliases();
  const l = w.post({op: 'lessons'});
  assert.equal(l.version, 1);
  assert.deepEqual(l.aliases.map(a => [a.spoken, a.cowId]), [['செவ்வாள', 'cow_7']]);
  assert.deepEqual(l.conflicts.map(c => c.spoken), ['லச்சு']);
  // A tampered dictionary fails closed.
  for (const [k, v] of w.files) if (k.endsWith('aliases-v1.json')) v.content = v.content.replace('cow_7', 'cow_9');
  assert.deepEqual(w.post({op: 'lessons'}), {error: 'manifest'});
});

check('regression gate keeps an active alias that new data would silently move', () => {
  const w = makeWorld();
  const learned = w.runtime.learnAliases([example(), example(), example({cowId: 'cow_8', cowSpoken: 'செவ்வாள'})],
    [{spoken: 'செவ்வாள', cowId: 'cow_7', evidence: 2}]);
  // Now it conflicts: the alias is withdrawn and asked about, never moved.
  assert.equal(JSON.stringify(learned.aliases), '[]');
  assert.equal(learned.conflicts.length, 1);
});

check('delete my data trashes only the caller files and schedules a rebuild', () => {
  const w = makeWorld();
  w.post({op: 'consent', text: true});
  w.post({op: 'example', example: example()});
  const r = w.post({op: 'deleteMine'});
  assert.equal(r.ok, true);
  assert.ok(r.removed >= 2);
  assert.ok([...w.files.entries()].filter(([k, v]) => k.includes('/examples/') && !v.dir).every(([, v]) => v.trashed));
  assert.ok(Object.keys(w.props).some(k => k.startsWith('VIMO_REBUILD_')));
});

check('errors never echo request content', () => {
  const w = makeWorld();
  const out = w.runtime.doPost({postData: {contents: '{"op":"milk","text":"கண்மணி' }});
  assert.deepEqual(out, {error: 'unavailable'});
});

for (const r of results) console.log(r.join(' | '));
const failed = results.filter(r => r[0] === 'FAIL').length;
console.log(`voice bridge: ${results.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
