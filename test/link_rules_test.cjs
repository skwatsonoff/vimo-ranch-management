// VIMO ID links and the shared ID namespace. Run with the Firebase Emulator
// Suite through test/run_rules_checks.cjs.
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, deleteDoc, collection, query, where, getDocs, runTransaction, serverTimestamp } = require('firebase/firestore');
const fs = require('node:fs');

(async () => {
  const env = await initializeTestEnvironment({ projectId: 'demo-vimo', firestore: { host: '127.0.0.1', port: 8088, rules: fs.readFileSync('firestore.rules', 'utf8') } });
  let checks = 0;
  try {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'usernames/kumar'), { uid: 'buyer', claimedAt: new Date() });
      await setDoc(doc(db, 'usernames/selva'), { uid: 'vendor', claimedAt: new Date() });
      await setDoc(doc(db, 'ranch_ids/green_farm'), { ranchId: 'green_farm', ownerUid: 'rancher' });
    });
    const vendor = env.authenticatedContext('vendor').firestore();
    const buyer = env.authenticatedContext('buyer').firestore();
    const rancher = env.authenticatedContext('rancher').firestore();
    const stranger = env.authenticatedContext('stranger').firestore();
    const anon = env.unauthenticatedContext().firestore();

    const link = (over = {}) => ({ fromUid: 'vendor', fromName: 'Selva Milk', toUid: 'buyer', toId: 'kumar', toKind: 'person', personName: 'Kumar', role: 'customer', status: 'pending', createdAt: serverTimestamp(), ...over });
    const ref = (db, id = 'vendor__p1') => doc(db, 'link_requests/' + id);

    // Sending
    await assertFails(setDoc(ref(vendor), link({ toUid: 'stranger' }))); checks++; // ID belongs to someone else
    await assertFails(setDoc(ref(vendor), link({ status: 'accepted' }))); checks++;
    await assertFails(setDoc(ref(vendor, 'buyer__p1'), link())); checks++; // not the sender's own ID
    await assertFails(setDoc(ref(vendor), link({ toUid: 'vendor', toId: 'selva' }))); checks++; // self
    await assertFails(setDoc(ref(vendor), link({ total: 500 }))); checks++; // only names travel
    await assertFails(setDoc(ref(stranger, 'vendor__p1'), link())); checks++;
    await assertFails(setDoc(ref(anon), link())); checks++;
    await assertSucceeds(setDoc(ref(vendor), link())); checks++;
    await assertSucceeds(setDoc(ref(vendor, 'vendor__p2'), link({ toUid: 'rancher', toId: 'green_farm', toKind: 'ranch', personName: 'Green Farm', role: 'supplier' }))); checks++;
    await assertFails(setDoc(ref(vendor, 'vendor__p3'), link({ toUid: 'buyer', toId: 'green_farm', toKind: 'ranch' }))); checks++;

    // Reading
    await assertSucceeds(getDoc(ref(buyer))); checks++;
    await assertSucceeds(getDocs(query(collection(buyer, 'link_requests'), where('toUid', '==', 'buyer'), where('status', '==', 'pending')))); checks++;
    await assertSucceeds(getDocs(query(collection(rancher, 'link_requests'), where('toUid', '==', 'rancher')))); checks++;
    await assertFails(getDoc(ref(stranger))); checks++;
    await assertFails(getDocs(collection(stranger, 'link_requests'))); checks++;
    await assertFails(getDoc(ref(anon))); checks++;

    // Answering
    await assertFails(updateDoc(ref(vendor), { status: 'accepted', respondedAt: serverTimestamp() })); checks++;
    await assertFails(updateDoc(ref(buyer), { status: 'accepted', respondedAt: serverTimestamp(), personName: 'Changed' })); checks++;
    await assertFails(updateDoc(ref(stranger), { status: 'accepted', respondedAt: serverTimestamp() })); checks++;
    await assertSucceeds(updateDoc(ref(buyer), { status: 'rejected', respondedAt: serverTimestamp() })); checks++;
    await assertFails(updateDoc(ref(buyer), { status: 'accepted', respondedAt: serverTimestamp() })); checks++; // answered once
    // The vendor may ask again after a rejection; it starts pending again.
    await assertSucceeds(setDoc(ref(vendor), link())); checks++;
    await assertSucceeds(updateDoc(ref(buyer), { status: 'accepted', respondedAt: serverTimestamp() })); checks++;
    await assertSucceeds(updateDoc(ref(rancher, 'vendor__p2'), { status: 'accepted', respondedAt: serverTimestamp() })); checks++;

    // Removing
    await assertFails(deleteDoc(ref(stranger))); checks++;
    await assertSucceeds(deleteDoc(ref(buyer))); checks++;
    await assertSucceeds(deleteDoc(ref(vendor, 'vendor__p2'))); checks++;

    // One ID is either a person or a ranch, never both.
    const claim = (db, uid, name) => runTransaction(db, async (tx) => {
      tx.set(doc(db, 'usernames/' + name), { uid, claimedAt: serverTimestamp() });
      tx.set(doc(db, 'users/' + uid), { username: name, usernameChangedAt: serverTimestamp() }, { merge: true });
    });
    await assertFails(claim(stranger, 'stranger', 'green_farm')); checks++;
    await assertSucceeds(claim(stranger, 'stranger', 'fresh_name')); checks++;
    await assertFails(setDoc(doc(stranger, 'ranch_ids/kumar'), { ranchId: 'kumar', ownerUid: 'stranger' })); checks++;
    await assertSucceeds(setDoc(doc(stranger, 'ranch_ids/new_farm'), { ranchId: 'new_farm', ownerUid: 'stranger' })); checks++;

    // The vendor's own person record keeps the linked ID (validated).
    await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), 'ranches/shop/members/vendor'), { role: 'Admin', status: 'active', active: true }));
    const person = { id: 'p1', kind: 'customer', name: 'Kumar', place: 'Erode', days: [], sessions: ['Morning'], paymentCycle: 'Daily', vimoId: 'kumar', vimoUid: 'buyer', vimoKind: 'person' };
    await assertSucceeds(setDoc(doc(vendor, 'ranches/shop/vendor_people/p1'), person)); checks++;
    await assertFails(setDoc(doc(vendor, 'ranches/shop/vendor_people/p1'), { ...person, vimoKind: 'admin' })); checks++;
    await assertFails(setDoc(doc(vendor, 'ranches/shop/vendor_people/p1'), { ...person, vimoId: 'x'.repeat(41) })); checks++;

    console.log(`VIMO ID link rules: ${checks} checks passed`);
  } finally {
    await env.cleanup();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
