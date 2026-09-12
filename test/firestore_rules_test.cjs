// Run with Firebase Emulator Suite. Requires @firebase/rules-unit-testing and firebase.
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, deleteDoc, runTransaction, serverTimestamp, Timestamp } = require('firebase/firestore');
const fs = require('node:fs');
const assert = require('node:assert/strict');

(async () => {
  const env = await initializeTestEnvironment({ projectId: 'demo-vimo', firestore: { host: '127.0.0.1', port: 8088, rules: fs.readFileSync('firestore.rules', 'utf8') } });
  let checks = 0;
  try {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const uid of ['owner', 'helper']) await setDoc(doc(db, `ranches/test/members/${uid}`), { active: true, status: 'active', role: uid === 'owner' ? 'Admin' : 'Data Entry' });
      await setDoc(doc(db, 'ranches/test/vendor_people/supplier'), { id: 'supplier', kind: 'supplier', name: 'Milk Farm', place: 'Erode', days: [], sessions: [], paymentCycle: 'Weekly' });
      await setDoc(doc(db, 'ranches/test/vendor_people/customer'), { id: 'customer', kind: 'customer', name: 'Kumar', place: 'Erode', days: [0, 1, 2, 3, 4, 5, 6], sessions: ['Morning', 'Evening'], paymentCycle: 'Monthly' });
    });
    const db = env.authenticatedContext('owner').firestore();
    const helper = env.authenticatedContext('helper').firestore();
    const outsider = env.authenticatedContext('outsider').firestore();
    const anon = env.unauthenticatedContext().firestore();
    const save = (database, uid, id, kind, quantity, price, paid = 0, payment = 0) => runTransaction(database, async tx => {
      const personId = kind === 'purchase' ? 'supplier' : 'customer';
      const entryRef = doc(database, `ranches/test/vendor_entries/${id}`);
      const stockRef = doc(database, 'ranches/test/vendor_stock/milk');
      const accountRef = doc(database, `ranches/test/vendor_accounts/${personId}`);
      const old = await tx.get(entryRef);
      if (old.exists()) return;
      const stock = await tx.get(stockRef), account = await tx.get(accountRef);
      const balance = stock.data()?.quantity ?? 0, due = account.data()?.due ?? 0;
      const amount = kind === 'payment' ? payment : quantity * price;
      tx.set(entryRef, { cloudId: id, kind, personId, personKind: kind === 'purchase' ? 'supplier' : 'customer', personName: 'Test', quantity, price, amount, paid, notes: '', createdByUid: uid, createdAt: new Date().toISOString(), serverCreatedAt: serverTimestamp() });
      tx.set(stockRef, { quantity: balance + (kind === 'purchase' ? quantity : kind === 'sale' ? -quantity : 0), entryId: id });
      tx.set(accountRef, { due: due + (kind === 'payment' ? -amount : amount - paid), entryId: id });
    });
    await assertSucceeds(save(db, 'owner', 'buy1', 'purchase', 10, 40, 100)); checks++;
    await assertSucceeds(save(helper, 'helper', 'buy2', 'purchase', 5, 42, 210)); checks++;
    await assertSucceeds(save(db, 'owner', 'sale1', 'sale', 3, 60, 30)); checks++;
    await assertSucceeds(save(db, 'owner', 'payment1', 'payment', 0, 0, 0, 100)); checks++;
    assert.equal((await getDoc(doc(db, 'ranches/test/vendor_stock/milk'))).data().quantity, 12); checks++;
    assert.equal((await getDoc(doc(db, 'ranches/test/vendor_accounts/customer'))).data().due, 50); checks++;
    await assertSucceeds(save(db, 'owner', 'buy1', 'purchase', 10, 40, 100)); checks++;
    assert.equal((await getDoc(doc(db, 'ranches/test/vendor_stock/milk'))).data().quantity, 12); checks++;
    await assertFails(save(db, 'owner', 'oversell', 'sale', 13, 60)); checks++;
    await assertFails(save(db, 'owner', 'overpay', 'payment', 0, 0, 0, 51)); checks++;
    await assertFails(updateDoc(doc(db, 'ranches/test/vendor_stock/milk'), { quantity: 999 })); checks++;
    await assertFails(getDoc(doc(outsider, 'ranches/test/vendor_stock/milk'))); checks++;
    await assertSucceeds(updateDoc(doc(db, 'ranches/test/vendor_entries/buy1'), { notes: 'Fresh milk', updatedAtMillis: Date.now() })); checks++;
    await assertFails(updateDoc(doc(helper, 'ranches/test/vendor_entries/buy1'), { notes: 'Another author' })); checks++;
    await assertFails(updateDoc(doc(db, 'ranches/test/vendor_entries/buy1'), { quantity: 100 })); checks++;
    await env.withSecurityRulesDisabled(async (ctx) => updateDoc(doc(ctx.firestore(), 'ranches/test/vendor_entries/buy1'), { serverCreatedAt: Timestamp.fromMillis(Date.now() - 360000) }));
    await assertFails(updateDoc(doc(db, 'ranches/test/vendor_entries/buy1'), { notes: 'Too late' })); checks++;
    const raced = await Promise.allSettled([save(db, 'owner', 'race1', 'sale', 8, 60), save(helper, 'helper', 'race2', 'sale', 8, 60)]);
    assert.equal(raced.filter(r => r.status === 'fulfilled').length, 1); checks++;
    assert.equal((await getDoc(doc(db, 'ranches/test/vendor_stock/milk'))).data().quantity, 4); checks++;
    const post = { authorUid: 'owner', ranchId: 'test', authorName: 'Kumar', text: 'Milk question', photo: '', voice: '', voiceSeconds: 0, tile: true, createdAt: serverTimestamp() };
    await assertSucceeds(setDoc(doc(db, 'social_posts/post1'), post)); checks++;
    await assertSucceeds(getDoc(doc(outsider, 'social_posts/post1'))); checks++;
    await assertFails(getDoc(doc(anon, 'social_posts/post1'))); checks++;
    await assertFails(setDoc(doc(outsider, 'social_posts/spoof'), { ...post, authorUid: 'outsider' })); checks++;
    await assertFails(updateDoc(doc(outsider, 'social_posts/post1'), { text: 'Changed' })); checks++;
    await assertSucceeds(setDoc(doc(outsider, 'social_posts/post1/likes/outsider'), { createdAt: serverTimestamp() })); checks++;
    await assertFails(setDoc(doc(outsider, 'social_posts/post1/likes/owner'), { createdAt: serverTimestamp() })); checks++;
    await assertSucceeds(setDoc(doc(helper, 'social_posts/post1/comments/c1'), { authorUid: 'helper', ranchId: 'test', authorName: 'Helper', text: 'Hello', createdAt: serverTimestamp() })); checks++;
    await assertFails(deleteDoc(doc(outsider, 'social_posts/post1/comments/c1'))); checks++;
    await assertFails(deleteDoc(doc(outsider, 'social_posts/post1'))); checks++;
    await assertSucceeds(deleteDoc(doc(db, 'social_posts/post1'))); checks++;
    console.log(`PASS: ${checks} Firestore stock, credit, concurrency, edit-window and social permission checks.`);
  } finally { await env.cleanup(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
