// Voice training: job requests in Firestore and recordings in Storage. Run
// with the Firebase Emulator Suite through test/run_rules_checks.cjs.
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, deleteDoc, serverTimestamp } = require('firebase/firestore');
const { ref, uploadBytes, uploadString, getBytes, deleteObject } = require('firebase/storage');
const fs = require('node:fs');

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-vimo',
    firestore: { host: '127.0.0.1', port: 8088, rules: fs.readFileSync('firestore.rules', 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: fs.readFileSync('storage.rules', 'utf8') },
  });
  let checks = 0;
  try {
    await env.clearFirestore();
    await env.clearStorage();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'ranches/r1/members/owner'), { role: 'Admin', active: true, status: 'active' });
      await setDoc(doc(db, 'voice_training_jobs/done'), { ownerUid: 'owner', ranchId: 'r1', languages: ['ta'], status: 'ready', wer: 0.21 });
    });
    const owner = env.authenticatedContext('owner');
    const other = env.authenticatedContext('other');
    const anon = env.unauthenticatedContext();

    // --- Firestore: voice_training_jobs -------------------------------------------
    const job = (over = {}) => ({ ownerUid: 'owner', ranchId: 'r1', languages: ['ta', 'en', 'ta-Latn'], status: 'requested', createdAt: serverTimestamp(), recordingCount: 120, minutes: 64.5, ...over });
    const jobRef = (ctx, id = 'j1') => doc(ctx.firestore(), 'voice_training_jobs/' + id);
    await assertSucceeds(setDoc(jobRef(owner), job())); checks++;
    await assertSucceeds(setDoc(jobRef(owner, 'j2'), job({ ranchId: '' }))); checks++; // no ranch yet
    await assertFails(setDoc(jobRef(owner, 'j3'), job({ status: 'ready' }))); checks++; // only the server marks ready
    await assertFails(setDoc(jobRef(owner, 'j4'), job({ ownerUid: 'other' }))); checks++; // not for someone else
    await assertFails(setDoc(jobRef(other, 'j5'), job({ ownerUid: 'other' }))); checks++; // not a member of r1
    await assertFails(setDoc(jobRef(owner, 'j6'), job({ wer: 0.1 }))); checks++; // no extra fields
    await assertFails(setDoc(jobRef(owner, 'j7'), job({ languages: [] }))); checks++;
    await assertFails(setDoc(jobRef(owner, 'j8'), job({ recordingCount: -1 }))); checks++;
    await assertFails(setDoc(jobRef(anon, 'j9'), job())); checks++;
    await assertSucceeds(getDoc(jobRef(owner, 'done'))); checks++;
    await assertFails(getDoc(jobRef(other, 'done'))); checks++; // not your job
    await assertFails(updateDoc(jobRef(owner, 'done'), { status: 'requested' })); checks++; // the server owns status
    await assertFails(deleteDoc(jobRef(owner, 'done'))); checks++;

    // --- Storage: training_data and language_packs ---------------------------------
    const wav = new Uint8Array(1024);
    const audio = (ctx, uid = 'owner', name = 'a1.wav') => ref(ctx.storage(), `training_data/${uid}/ta/${name}`);
    await assertSucceeds(uploadBytes(audio(owner), wav, { contentType: 'audio/wav' })); checks++;
    await assertSucceeds(uploadString(audio(owner, 'owner', 'a1.json'), '{"transcript":"லட்சுமி 5 லிட்டர்"}', 'raw', { contentType: 'application/json' })); checks++;
    await assertFails(uploadBytes(audio(owner, 'owner', 'a2.mp3'), wav, { contentType: 'audio/mpeg' })); checks++; // wav or json only
    await assertFails(uploadBytes(audio(owner, 'owner', 'big.wav'), new Uint8Array(10 * 1024 * 1024 + 1), { contentType: 'audio/wav' })); checks++; // 10 MB limit
    await assertFails(uploadBytes(audio(other, 'owner', 'x.wav'), wav, { contentType: 'audio/wav' })); checks++; // not your folder
    await assertFails(uploadBytes(audio(anon), wav, { contentType: 'audio/wav' })); checks++;
    await assertSucceeds(getBytes(audio(owner))); checks++;
    await assertFails(getBytes(audio(other))); checks++;
    await assertFails(deleteObject(audio(other))); checks++;
    await assertSucceeds(deleteObject(audio(owner))); checks++;

    await env.withSecurityRulesDisabled(async (ctx) => {
      await uploadString(ref(ctx.storage(), 'language_packs/manifest.json'), '{"schema":1,"packs":[]}', 'raw', { contentType: 'application/json' });
    });
    await assertSucceeds(getBytes(ref(anon.storage(), 'language_packs/manifest.json'))); checks++; // public read
    await assertFails(uploadString(ref(owner.storage(), 'language_packs/manifest.json'), '{}', 'raw', { contentType: 'application/json' })); checks++; // no client writes
    console.log(`voice training rules: ${checks} checks passed`);
  } finally {
    await env.cleanup();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
