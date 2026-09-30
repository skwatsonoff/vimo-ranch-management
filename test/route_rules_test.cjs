// Run with the demo-vimo emulator only. Never targets a production project.
// Route map loans, milk clearance and optional home locations.
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc, deleteDoc, collection, query, where, getDocs, serverTimestamp, Timestamp} = require('firebase/firestore');
const fs = require('node:fs');

(async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-vimo', firestore: {host: '127.0.0.1', port: 8088, rules: fs.readFileSync('firestore.rules', 'utf8')}});
  let checks = 0;
  try {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'ranches/route/members/owner'), {active: true, status: 'active', role: 'Admin'});
      await setDoc(doc(db, 'ranches/route/vendor_people/customer'), {id: 'customer', kind: 'customer', name: 'Kumar', place: 'Erode', days: [], sessions: ['Morning'], paymentCycle: 'Daily'});
    });
    const owner = env.authenticatedContext('owner').firestore();
    const friend = env.authenticatedContext('friend').firestore();
    const stranger = env.authenticatedContext('stranger').firestore();

    // Lending a route.
    const inDays = (d) => Timestamp.fromMillis(Date.now() + d * 86400000);
    const share = {
      ownerUid: 'owner', ownerName: 'Owner', recipientUid: 'friend', routeName: 'Morning round',
      route: {path: [{lat: 11.1, lng: 78.1}, {lat: 11.2, lng: 78.2}], stops: [{id: 'customer', name: 'Kumar', place: 'Erode', litres: 2}], notes: []},
      collectLater: true, status: 'active', response: 'pending', progress: {},
      expiresAt: inDays(1), createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    };
    const ref = doc(owner, 'route_shares/loan');
    await assertSucceeds(setDoc(ref, share)); checks++;
    await assertFails(setDoc(doc(owner, 'route_shares/self'), {...share, recipientUid: 'owner'})); checks++;
    await assertFails(setDoc(doc(owner, 'route_shares/long'), {...share, expiresAt: inDays(9)})); checks++;
    await assertFails(setDoc(doc(owner, 'route_shares/leak'), {...share, route: {...share.route, contacts: ['123']}})); checks++;
    await assertFails(setDoc(doc(stranger, 'route_shares/forged'), {...share, ownerUid: 'owner'})); checks++;
    await assertSucceeds(getDoc(doc(friend, 'route_shares/loan'))); checks++;
    await assertFails(getDoc(doc(stranger, 'route_shares/loan'))); checks++;
    await assertSucceeds(getDocs(query(collection(friend, 'route_shares'), where('recipientUid', '==', 'friend')))); checks++;
    await assertSucceeds(getDocs(query(collection(owner, 'route_shares'), where('ownerUid', '==', 'owner')))); checks++;
    await assertFails(getDocs(collection(stranger, 'route_shares'))); checks++;

    // The recipient answers and reports deliveries, nothing else.
    const friendRef = doc(friend, 'route_shares/loan');
    await assertSucceeds(updateDoc(friendRef, {response: 'accepted', updatedAt: serverTimestamp()})); checks++;
    await assertSucceeds(updateDoc(friendRef, {progress: {customer: {s: 'done', q: 2.5}}, updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(friendRef, {expiresAt: inDays(5), updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(friendRef, {status: 'active', routeName: 'Mine', updatedAt: serverTimestamp()})); checks++;

    // The owner extends or stops; a stopped loan takes no more progress.
    await assertSucceeds(updateDoc(ref, {expiresAt: inDays(3), status: 'active', updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(ref, {expiresAt: inDays(20), updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(ref, {progress: {}, updatedAt: serverTimestamp()})); checks++;
    await assertSucceeds(updateDoc(ref, {status: 'stopped', updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(friendRef, {progress: {customer: {s: 'skipped'}}, updatedAt: serverTimestamp()})); checks++;
    await assertFails(deleteDoc(friendRef)); checks++;
    await assertSucceeds(deleteDoc(ref)); checks++;

    // Milk clearance leaves stock at no charge, to the fridge or a person.
    const clearance = {cloudId: 'clear1', syncMode: 'local_v3', stockScope: 'vendor_v2', kind: 'clearance', personId: '_fridge', personKind: 'fridge', personName: 'Fridge', quantity: 3, price: 0, amount: 0, paid: 0, notes: '', createdByUid: 'owner', createdAt: new Date().toISOString(), updatedAtMillis: Date.now(), serverCreatedAt: serverTimestamp()};
    await assertSucceeds(setDoc(doc(owner, 'ranches/route/vendor_entries/clear1'), clearance)); checks++;
    await assertSucceeds(setDoc(doc(owner, 'ranches/route/vendor_entries/clear2'), {...clearance, cloudId: 'clear2', personId: 'customer', personKind: 'customer', personName: 'Kumar'})); checks++;
    await assertFails(setDoc(doc(owner, 'ranches/route/vendor_entries/clear3'), {...clearance, cloudId: 'clear3', amount: 50, price: 50, quantity: 1})); checks++;
    await assertFails(setDoc(doc(owner, 'ranches/route/vendor_entries/clear4'), {...clearance, cloudId: 'clear4', personId: 'someone', personKind: 'fridge'})); checks++;
    await assertFails(setDoc(doc(owner, 'ranches/route/vendor_entries/clear5'), {...clearance, cloudId: 'clear5', personId: 'customer', personKind: 'supplier'})); checks++;
    await assertFails(setDoc(doc(owner, 'ranches/route/vendor_entries/clear6'), {...clearance, cloudId: 'clear6', quantity: 0})); checks++;
    await assertFails(setDoc(doc(stranger, 'ranches/route/vendor_entries/clear7'), {...clearance, cloudId: 'clear7', createdByUid: 'stranger'})); checks++;

    // A home location is optional; null clears it; nonsense is refused.
    const personRef = doc(owner, 'ranches/route/vendor_people/customer');
    await assertSucceeds(updateDoc(personRef, {lat: 11.34, lng: 77.71})); checks++;
    await assertSucceeds(updateDoc(personRef, {lat: null, lng: null})); checks++;
    await assertFails(updateDoc(personRef, {lat: 120, lng: 77.71})); checks++;
    await assertFails(updateDoc(personRef, {lat: 'north', lng: 77.71})); checks++;
    console.log(`${checks} route, clearance and location security checks passed`);
  } finally { await env.cleanup(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
