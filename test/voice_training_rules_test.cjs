// Voice training: job requests, recordings and words in Firestore. Run
// with the Firebase Emulator Suite through test/run_rules_checks.cjs.
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, deleteDoc, serverTimestamp, Bytes } = require('firebase/firestore');
const fs = require('node:fs');

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-vimo',
    firestore: { host: '127.0.0.1', port: 8088, rules: fs.readFileSync('firestore.rules', 'utf8') },
  });
  let checks = 0;
  try {
    await env.clearFirestore();
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

    // --- Firestore: recordings and words ----------------------------------------------
    const wav = (n = 1024) => Bytes.fromUint8Array(new Uint8Array(n));
    const rec = (over = {}) => ({ ownerUid: 'owner', sidecar: '{"transcript":"லட்சுமி 5 லிட்டர்"}', wav: wav(), createdAt: serverTimestamp(), ...over });
    const recRef = (ctx, id = 'owner_r1') => doc(ctx.firestore(), 'voice_training_audio/' + id);
    await assertSucceeds(setDoc(recRef(owner), rec())); checks++;
    await assertFails(setDoc(recRef(owner, 'other_r2'), rec())); checks++; // id must start with your uid
    await assertFails(setDoc(recRef(other, 'other_r3'), rec())); checks++; // not your recording
    await assertFails(setDoc(recRef(owner, 'owner_r4'), rec({ wav: wav(1000001) }))); checks++; // under 1 MB
    await assertFails(setDoc(recRef(owner, 'owner_r5'), rec({ wav: 'not bytes' }))); checks++;
    await assertFails(setDoc(recRef(owner, 'owner_r6'), rec({ name: 'Selvi' }))); checks++; // no extra fields
    await assertFails(setDoc(recRef(anon, 'owner_r7'), rec())); checks++;
    await assertSucceeds(getDoc(recRef(owner))); checks++;
    await assertFails(getDoc(recRef(other))); checks++;
    await assertFails(updateDoc(recRef(owner), { sidecar: '{}' })); checks++; // recordings are not edited
    await assertFails(deleteDoc(recRef(other))); checks++;
    await assertSucceeds(deleteDoc(recRef(owner))); checks++;

    const lex = (over = {}) => ({ ownerUid: 'owner', json: '{"cows":[]}', updatedAt: serverTimestamp(), ...over });
    const lexRef = (ctx, uid = 'owner') => doc(ctx.firestore(), 'voice_training_lexicon/' + uid);
    await assertSucceeds(setDoc(lexRef(owner), lex())); checks++;
    await assertSucceeds(setDoc(lexRef(owner), lex({ json: '{"cows":[{"name":"Lakshmi"}]}' }))); checks++;
    await assertFails(setDoc(lexRef(other, 'owner'), lex())); checks++;
    await assertFails(getDoc(lexRef(other, 'owner'))); checks++;
    await assertSucceeds(getDoc(lexRef(owner))); checks++;
    console.log(`voice training rules: ${checks} checks passed`);
  } finally {
    await env.cleanup();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
