// Security audit checks: signed-out access, cross-ranch isolation, owner
// protection and join-request validation. Run with the Firebase Emulator
// Suite through test/run_rules_checks.cjs.
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, deleteDoc, collection, getDocs, serverTimestamp } = require('firebase/firestore');
const fs = require('node:fs');

(async () => {
  const env = await initializeTestEnvironment({ projectId: 'demo-vimo', firestore: { host: '127.0.0.1', port: 8088, rules: fs.readFileSync('firestore.rules', 'utf8') } });
  let checks = 0;
  try {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'usernames/selva'), { uid: 'owner', claimedAt: new Date() });
      await setDoc(doc(db, 'ranch_ids/farm-a'), { ranchId: 'farm-a', ownerUid: 'owner' });
      await setDoc(doc(db, 'ranches/farm-a'), { ranchId: 'farm-a', farmName: 'Farm A', ownerUid: 'owner' });
      await setDoc(doc(db, 'ranches/farm-a/members/owner'), { role: 'Admin', status: 'active', active: true });
      await setDoc(doc(db, 'ranches/farm-a/members/manager'), { role: 'Admin', status: 'active', active: true });
      await setDoc(doc(db, 'ranches/farm-a/members/helper'), { role: 'Data Entry', status: 'active', active: true });
      await setDoc(doc(db, 'ranches/farm-a/milk_records/m1'), { cow: 'Lakshmi', quantity: 4 });
      await setDoc(doc(db, 'ranches/farm-b'), { ranchId: 'farm-b', farmName: 'Farm B', ownerUid: 'other' });
      await setDoc(doc(db, 'ranches/farm-b/members/other'), { role: 'Admin', status: 'active', active: true });
      await setDoc(doc(db, 'ranches/farm-b/milk_records/b1'), { cow: 'Ganga', quantity: 6 });
    });
    const anon = env.unauthenticatedContext().firestore();
    const owner = env.authenticatedContext('owner').firestore();
    const manager = env.authenticatedContext('manager').firestore();
    const helper = env.authenticatedContext('helper').firestore();
    const other = env.authenticatedContext('other').firestore();
    const stranger = env.authenticatedContext('stranger').firestore();

    // 1. Signed-out people can read or write nothing.
    // Sign-up checks one VIMO ID before the account exists; listing is denied.
    await assertSucceeds(getDoc(doc(anon, 'usernames/selva'))); checks++;
    await assertFails(getDocs(collection(anon, 'usernames'))); checks++;
    await assertFails(getDocs(collection(stranger, 'usernames'))); checks++;
    await assertFails(getDoc(doc(anon, 'ranches/farm-a'))); checks++;
    await assertFails(getDoc(doc(anon, 'ranches/farm-a/milk_records/m1'))); checks++;
    await assertFails(getDocs(collection(anon, 'ranches/farm-a/milk_records'))); checks++;
    await assertFails(setDoc(doc(anon, 'ranches/farm-a/milk_records/x'), { quantity: 1 })); checks++;
    await assertFails(getDoc(doc(anon, 'profiles/owner'))); checks++;
    await assertFails(getDoc(doc(anon, 'social_posts/p1'))); checks++;
    await assertSucceeds(getDoc(doc(stranger, 'usernames/selva'))); checks++;

    // 2. One ranch cannot see or change another ranch.
    await assertSucceeds(getDoc(doc(owner, 'ranches/farm-a/milk_records/m1'))); checks++;
    await assertSucceeds(setDoc(doc(helper, 'ranches/farm-a/milk_records/m2'), { cow: 'Ponni', quantity: 3 })); checks++;
    await assertFails(getDoc(doc(other, 'ranches/farm-a/milk_records/m1'))); checks++;
    await assertFails(getDocs(collection(other, 'ranches/farm-a/milk_records'))); checks++;
    await assertFails(setDoc(doc(other, 'ranches/farm-a/milk_records/evil'), { quantity: 99 })); checks++;
    await assertFails(getDoc(doc(owner, 'ranches/farm-b/milk_records/b1'))); checks++;
    await assertFails(getDoc(doc(stranger, 'ranches/farm-a'))); checks++;
    await assertFails(setDoc(doc(stranger, 'ranches/farm-a/members/stranger'), { role: 'Admin', status: 'active' })); checks++;

    // 3. Anything not listed is denied.
    await assertFails(setDoc(doc(owner, 'anything/new'), { a: 1 })); checks++;
    await assertFails(getDoc(doc(owner, 'anything/new'))); checks++;
    await assertFails(setDoc(doc(owner, 'ranches/farm-a/unknown/doc'), { a: 1 })); checks++;

    // 4. Only the owner decides who owns the ranch.
    await assertSucceeds(updateDoc(doc(manager, 'ranches/farm-a'), { farmName: 'Farm A North' })); checks++;
    await assertFails(updateDoc(doc(manager, 'ranches/farm-a'), { ownerUid: 'manager' })); checks++;
    await assertFails(updateDoc(doc(helper, 'ranches/farm-a'), { farmName: 'Helper farm' })); checks++;
    await assertSucceeds(updateDoc(doc(owner, 'ranches/farm-a'), { farmName: 'Farm A' })); checks++;

    // 5. Another admin cannot demote or remove the owner.
    await assertFails(updateDoc(doc(manager, 'ranches/farm-a/members/owner'), { role: 'Viewer' })); checks++;
    await assertFails(deleteDoc(doc(manager, 'ranches/farm-a/members/owner'))); checks++;
    await assertSucceeds(updateDoc(doc(manager, 'ranches/farm-a/members/helper'), { role: 'Editor' })); checks++;
    await assertSucceeds(updateDoc(doc(owner, 'ranches/farm-a/members/manager'), { role: 'Editor' })); checks++;
    await assertFails(updateDoc(doc(helper, 'ranches/farm-a/members/helper'), { role: 'Admin' })); checks++;

    // 6. A join request starts as pending and carries only its own details.
    const request = { uid: 'stranger', name: 'Kumar', email: 'kumar@example.com', status: 'pending', requestedAt: serverTimestamp() };
    await assertFails(setDoc(doc(stranger, 'ranches/farm-a/join_requests/stranger'), { ...request, status: 'approved' })); checks++;
    await assertFails(setDoc(doc(stranger, 'ranches/farm-a/join_requests/stranger'), { ...request, role: 'Admin' })); checks++;
    await assertFails(setDoc(doc(stranger, 'ranches/farm-a/join_requests/stranger'), { ...request, name: 'x'.repeat(121) })); checks++;
    await assertFails(setDoc(doc(stranger, 'ranches/farm-a/join_requests/someone'), { ...request })); checks++;
    await assertSucceeds(setDoc(doc(stranger, 'ranches/farm-a/join_requests/stranger'), request)); checks++;
    await assertSucceeds(getDoc(doc(owner, 'ranches/farm-a/join_requests/stranger'))); checks++;
    await assertFails(getDoc(doc(helper, 'ranches/farm-a/join_requests/stranger'))); checks++;
    await assertFails(getDoc(doc(stranger, 'ranches/farm-a/milk_records/m1'))); checks++;

    console.log(`Security audit rules: ${checks} checks passed`);
  } finally {
    await env.cleanup();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
