// Milk shop counter entries. Run with the Firebase Emulator Suite through
// test/run_rules_checks.cjs.
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, deleteDoc, serverTimestamp } = require('firebase/firestore');
const fs = require('node:fs');

(async () => {
  const env = await initializeTestEnvironment({ projectId: 'demo-vimo', firestore: { host: '127.0.0.1', port: 8088, rules: fs.readFileSync('firestore.rules', 'utf8') } });
  let checks = 0;
  try {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'ranches/shop'), { ownerUid: 'owner' });
      await setDoc(doc(db, 'ranches/shop/members/owner'), { role: 'Admin', status: 'active', active: true });
      await setDoc(doc(db, 'ranches/shop/members/helper'), { role: 'Data Entry', status: 'active', active: true });
      await setDoc(doc(db, 'ranches/shop/members/gone'), { role: 'Admin', status: 'removed', active: false });
    });
    const owner = env.authenticatedContext('owner').firestore();
    const helper = env.authenticatedContext('helper').firestore();
    const gone = env.authenticatedContext('gone').firestore();
    const stranger = env.authenticatedContext('stranger').firestore();

    const sale = (id, uid, over = {}) => ({ cloudId: id, kind: 'sale', itemId: 'milk', itemName: 'Milk', unit: 'litre', quantity: 1.5, price: 50, amount: 75, voided: false, notes: '', date: '2026-10-17', time: '08:30', createdAt: '2026-10-17T08:30:00', createdByUid: uid, addedBy: 'Selva', updatedAtMillis: 1, updatedAtText: 't1', updatedBy: 'Selva', serverCreatedAt: serverTimestamp(), ...over });
    const ref = (db, id) => doc(db, 'ranches/shop/shop_entries/' + id);

    // Creating
    await assertSucceeds(setDoc(ref(owner, 's1'), sale('s1', 'owner'))); checks++;
    await assertSucceeds(setDoc(ref(helper, 's2'), sale('s2', 'helper', { itemId: 'item_1', itemName: 'Biscuit', unit: 'count', quantity: 3, price: 10, amount: 30 }))); checks++;
    await assertSucceeds(setDoc(ref(owner, 'k1'), sale('k1', 'owner', { kind: 'stock', itemId: 'curd', itemName: 'Curd', quantity: 5, price: 0, amount: 0 }))); checks++;
    await assertSucceeds(setDoc(ref(owner, 's9'), sale('s9', 'owner', { voided: true }))); checks++; // cancelled before it synced
    await assertFails(setDoc(ref(owner, 's3'), sale('s3', 'owner', { amount: 10 }))); checks++; // wrong total
    await assertFails(setDoc(ref(owner, 's3'), sale('s3', 'owner', { price: 0, amount: 0 }))); checks++; // free sale
    await assertFails(setDoc(ref(owner, 'k2'), sale('k2', 'owner', { kind: 'stock', price: 5, amount: 7.5 }))); checks++;
    await assertFails(setDoc(ref(owner, 's3'), sale('s3', 'owner', { quantity: -1, amount: -50 }))); checks++;
    await assertFails(setDoc(ref(owner, 's3'), sale('s3', 'owner', { unit: 'box' }))); checks++;
    await assertFails(setDoc(ref(owner, 's3'), sale('s3', 'owner', { kind: 'refund' }))); checks++;
    await assertFails(setDoc(ref(owner, 's3'), sale('s3', 'owner', { itemName: '' }))); checks++;
    await assertFails(setDoc(ref(owner, 's3'), sale('s4', 'owner'))); checks++; // id mismatch
    await assertFails(setDoc(ref(helper, 's3'), sale('s3', 'owner'))); checks++; // someone else's name
    await assertFails(setDoc(ref(owner, 's3'), sale('s3', 'owner', { serverCreatedAt: new Date(0) }))); checks++;
    await assertFails(setDoc(ref(gone, 's3'), sale('s3', 'gone'))); checks++;
    await assertFails(setDoc(ref(stranger, 's3'), sale('s3', 'stranger'))); checks++;

    // Reading
    await assertSucceeds(getDoc(ref(helper, 's1'))); checks++;
    await assertFails(getDoc(ref(stranger, 's1'))); checks++;
    await assertFails(getDoc(ref(gone, 's1'))); checks++;

    // Cancelling: only the seller, only the cancel mark.
    await assertFails(updateDoc(ref(helper, 's1'), { voided: true, updatedAtMillis: 2 })); checks++;
    await assertFails(updateDoc(ref(owner, 's1'), { voided: true, amount: 0, updatedAtMillis: 2 })); checks++;
    await assertFails(updateDoc(ref(owner, 's1'), { quantity: 9, updatedAtMillis: 2 })); checks++;
    await assertFails(updateDoc(ref(owner, 'k1'), { voided: true, updatedAtMillis: 2 })); checks++; // stock rows stay
    await assertSucceeds(updateDoc(ref(owner, 's1'), { voided: true, updatedAtMillis: 2, updatedAtText: 't2', updatedBy: 'Selva' })); checks++;
    await assertFails(updateDoc(ref(owner, 's1'), { voided: false, updatedAtMillis: 3 })); checks++; // no un-cancel
    await assertSucceeds(updateDoc(ref(helper, 's2'), { voided: true, updatedAtMillis: 2 })); checks++;

    // Never deleted
    await assertFails(deleteDoc(ref(owner, 's1'))); checks++;
    await assertFails(deleteDoc(ref(helper, 's2'))); checks++;

    console.log(`Shop rules: ${checks} checks passed`);
  } catch (error) {
    console.error(error);
    process.exitCode = 1;
  } finally {
    await env.cleanup();
  }
})();
