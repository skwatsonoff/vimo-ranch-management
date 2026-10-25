// Nearby milk search: listings, requests and buyer-only reviews. Run with the
// Firebase Emulator Suite through test/run_rules_checks.cjs.
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, deleteDoc, collection, query, where, getDocs, serverTimestamp, Timestamp } = require('firebase/firestore');
const fs = require('node:fs');

(async () => {
  const env = await initializeTestEnvironment({ projectId: 'demo-vimo', firestore: { host: '127.0.0.1', port: 8088, rules: fs.readFileSync('firestore.rules', 'utf8') } });
  let checks = 0;
  try {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'link_requests/vendor__p1'), { fromUid: 'vendor', toUid: 'linked', status: 'accepted' });
      await setDoc(doc(db, 'link_requests/vendor__p2'), { fromUid: 'vendor', toUid: 'stranger', status: 'rejected' });
    });
    const vendor = env.authenticatedContext('vendor').firestore();
    const buyer = env.authenticatedContext('buyer').firestore();
    const linked = env.authenticatedContext('linked').firestore();
    const stranger = env.authenticatedContext('stranger').firestore();
    const anon = env.unauthenticatedContext().firestore();

    // Chennai 13.0827, 80.2707 -> grid 6541, 40135 -> cell 261:1605
    const listing = (over = {}) => ({ name: 'Selva Milk', kind: 'vendor', gridLat: 6541, gridLng: 40135, cell: '261:1605', price: 60, morning: { start: '05:30', end: '08:00' }, evening: {}, active: true, holiday: false, onRide: false, updatedAt: serverTimestamp(), ...over });
    const listRef = (db, uid = 'vendor') => doc(db, 'vendor_listings/' + uid);

    // Listing
    await assertFails(setDoc(listRef(vendor), listing({ lat: 13.0827 }))); checks++; // exact place never stored
    await assertFails(setDoc(listRef(vendor), listing({ gridLat: 6541.5 }))); checks++; // grid only
    await assertFails(setDoc(listRef(vendor), listing({ cell: '1:1' }))); checks++; // cell must match grid
    // Ranches can be listed too; any other kind cannot.
    await assertFails(setDoc(listRef(vendor), listing({ kind: 'farm' }))); checks++;
    // The search name must be the real name in lower case.
    await assertFails(setDoc(listRef(vendor), listing({ nameFold: 'other name' }))); checks++;
    await assertFails(setDoc(listRef(vendor), listing({ morning: { start: '5:30', end: '08:00' } }))); checks++;
    await assertFails(setDoc(listRef(buyer, 'vendor'), listing())); checks++; // someone else's listing
    await assertFails(setDoc(listRef(anon), listing())); checks++;
    await assertSucceeds(setDoc(listRef(vendor), listing({ kind: 'ranch', nameFold: 'selva milk' }))); checks++;
    await assertSucceeds(getDocs(query(collection(buyer, 'vendor_listings'), where('nameFold', '>=', 'sel'), where('nameFold', '<', 'sel\uf8ff')))); checks++;
    await assertSucceeds(setDoc(listRef(vendor), listing())); checks++;
    // Negative grid (west/south) also matches its cell.
    await assertSucceeds(setDoc(listRef(stranger, 'stranger'), listing({ gridLat: -6541, gridLng: -40135, cell: '-262:-1606' }))); checks++;
    await assertSucceeds(updateDoc(listRef(vendor), { onRide: true, rideAt: serverTimestamp(), updatedAt: serverTimestamp() })); checks++;
    await assertSucceeds(getDoc(listRef(buyer))); checks++;
    await assertSucceeds(getDocs(query(collection(buyer, 'vendor_listings'), where('cell', 'in', ['261:1605', '261:1606'])))); checks++;
    await assertFails(getDoc(listRef(anon))); checks++;
    await assertFails(deleteDoc(listRef(buyer))); checks++;

    // Requests
    const req = (over = {}) => ({ buyerUid: 'buyer', buyerName: 'Kumar', vendorUid: 'vendor', vendorName: 'Selva Milk', kind: 'today', litres: 1.5, session: 'Morning', time: '06:30', days: [], payment: '', home: { lat: 13.08, lng: 80.27 }, note: '', status: 'pending', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over });
    const rRef = (db, id = 'r1') => doc(db, 'milk_requests/' + id);
    await assertFails(setDoc(rRef(buyer), req({ status: 'accepted' }))); checks++;
    await assertFails(setDoc(rRef(buyer), req({ buyerUid: 'linked' }))); checks++;
    await assertFails(setDoc(rRef(vendor), req({ buyerUid: 'vendor' }))); checks++; // to oneself
    await assertFails(setDoc(rRef(buyer), req({ litres: 0 }))); checks++;
    await assertFails(setDoc(rRef(buyer), req({ litres: 80 }))); checks++;
    await assertFails(setDoc(rRef(buyer), req({ kind: 'regular' }))); checks++; // regular needs days + payment
    await assertFails(setDoc(rRef(buyer), req({ days: ['Mon'] }))); checks++; // today has no days
    await assertFails(setDoc(rRef(buyer), req({ time: '6:30' }))); checks++;
    await assertFails(setDoc(rRef(buyer), req({ home: { lat: 200, lng: 80 } }))); checks++;
    await assertFails(setDoc(rRef(buyer), req({ vendorPoint: { lat: 1, lng: 1 } }))); checks++;
    await assertFails(setDoc(rRef(buyer), req({ vendorUid: 'nobody' }))); checks++; // not listed
    await assertSucceeds(setDoc(rRef(buyer), req())); checks++;
    await assertSucceeds(setDoc(rRef(buyer, 'r2'), req({ kind: 'regular', days: ['Mon', 'Wed', 'Fri'], payment: 'monthly', time: '', home: {} }))); checks++;
    await assertSucceeds(setDoc(rRef(buyer, 'r3'), req())); checks++;

    // Reading: only the two sides
    await assertSucceeds(getDoc(rRef(vendor))); checks++;
    await assertSucceeds(getDocs(query(collection(vendor, 'milk_requests'), where('vendorUid', '==', 'vendor'), where('status', '==', 'pending')))); checks++;
    await assertSucceeds(getDocs(query(collection(buyer, 'milk_requests'), where('buyerUid', '==', 'buyer')))); checks++;
    await assertFails(getDoc(rRef(stranger))); checks++;
    await assertFails(getDocs(collection(stranger, 'milk_requests'))); checks++;

    // A review before any acceptance is refused.
    const review = (over = {}) => ({ stars: 5, text: 'Fresh milk, on time', buyerName: 'Kumar', proof: 'r1', proofKind: 'request', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over });
    const revRef = (db, who = 'buyer', v = 'vendor') => doc(db, `vendor_listings/${v}/reviews/${who}`);
    await assertFails(setDoc(revRef(buyer), review())); checks++;

    // Answering
    await assertFails(updateDoc(rRef(buyer), { status: 'accepted', acceptedAt: serverTimestamp(), updatedAt: serverTimestamp() })); checks++; // buyer cannot accept their own
    await assertFails(updateDoc(rRef(vendor), { status: 'accepted', acceptedAt: serverTimestamp(), updatedAt: serverTimestamp() })); checks++; // must share the place
    await assertFails(updateDoc(rRef(vendor), { status: 'accepted', acceptedAt: serverTimestamp(), vendorPoint: { lat: 13.08 }, updatedAt: serverTimestamp() })); checks++;
    await assertFails(updateDoc(rRef(vendor), { status: 'accepted', acceptedAt: serverTimestamp(), vendorPoint: { lat: 13.08, lng: 80.27 }, litres: 9, updatedAt: serverTimestamp() })); checks++; // cannot change the order
    await assertFails(updateDoc(rRef(stranger), { status: 'declined', updatedAt: serverTimestamp() })); checks++;
    await assertSucceeds(updateDoc(rRef(vendor), { status: 'accepted', acceptedAt: serverTimestamp(), vendorPoint: { lat: 13.0827, lng: 80.2707 }, updatedAt: serverTimestamp() })); checks++;
    await assertFails(updateDoc(rRef(vendor), { status: 'declined', updatedAt: serverTimestamp() })); checks++; // answered once

    // Offer path: vendor proposes, buyer agrees, vendor then shares the place.
    await assertFails(updateDoc(rRef(vendor, 'r2'), { status: 'offered', offerPrice: 64, vendorPoint: { lat: 1, lng: 1 }, updatedAt: serverTimestamp() })); checks++; // no place before agreement
    await assertFails(updateDoc(rRef(vendor, 'r2'), { status: 'offered', offerTime: '25:00', updatedAt: serverTimestamp() })); checks++;
    await assertSucceeds(updateDoc(rRef(vendor, 'r2'), { status: 'offered', offerTime: '06:00', offerPrice: 64, updatedAt: serverTimestamp() })); checks++;
    await assertFails(updateDoc(rRef(buyer, 'r2'), { status: 'accepted', acceptedAt: serverTimestamp(), offerPrice: 10, updatedAt: serverTimestamp() })); checks++;
    await assertSucceeds(updateDoc(rRef(buyer, 'r2'), { status: 'accepted', acceptedAt: serverTimestamp(), updatedAt: serverTimestamp() })); checks++;
    await assertFails(updateDoc(rRef(buyer, 'r2'), { vendorPoint: { lat: 1, lng: 1 }, updatedAt: serverTimestamp() })); checks++;
    await assertSucceeds(updateDoc(rRef(vendor, 'r2'), { vendorPoint: { lat: 13.0827, lng: 80.2707 }, updatedAt: serverTimestamp() })); checks++;

    // Declining and cancelling
    await assertSucceeds(updateDoc(rRef(vendor, 'r3'), { status: 'declined', updatedAt: serverTimestamp() })); checks++;
    await assertFails(updateDoc(rRef(buyer, 'r3'), { status: 'cancelled', cancelledBy: 'buyer', updatedAt: serverTimestamp() })); checks++; // already closed
    await assertFails(updateDoc(rRef(buyer, 'r2'), { status: 'cancelled', cancelledBy: 'vendor', updatedAt: serverTimestamp() })); checks++; // must name oneself
    await assertSucceeds(updateDoc(rRef(buyer, 'r2'), { status: 'cancelled', cancelledBy: 'buyer', updatedAt: serverTimestamp() })); checks++;
    await assertFails(deleteDoc(rRef(buyer))); checks++;
    await assertFails(deleteDoc(rRef(vendor))); checks++;

    // Reviews: only a real buyer, one each, 1-5 stars.
    await assertFails(setDoc(revRef(buyer), review({ stars: 6 }))); checks++;
    await assertFails(setDoc(revRef(buyer), review({ stars: 4.5 }))); checks++;
    await assertFails(setDoc(revRef(buyer), review({ proof: 'r3' }))); checks++; // declined request
    await assertFails(setDoc(revRef(stranger, 'stranger'), review({ buyerName: 'X' }))); checks++; // not their request
    await assertFails(setDoc(revRef(buyer, 'linked'), review())); checks++; // writing as someone else
    await assertSucceeds(setDoc(revRef(buyer), review())); checks++;
    // A cancelled request that was accepted earlier still proves a real buyer.
    await assertSucceeds(setDoc(revRef(buyer), review({ proof: 'r2', stars: 4, createdAt: (await getDoc(revRef(buyer))).data().createdAt }))); checks++;
    await assertFails(updateDoc(revRef(buyer), { createdAt: Timestamp.fromMillis(0), updatedAt: serverTimestamp() })); checks++;
    await assertSucceeds(setDoc(revRef(linked, 'linked'), review({ buyerName: 'Ravi', proof: 'vendor__p1', proofKind: 'link' }))); checks++;
    await assertFails(setDoc(revRef(stranger, 'stranger'), review({ buyerName: 'X', proof: 'vendor__p2', proofKind: 'link' }))); checks++; // rejected link
    await assertFails(setDoc(revRef(vendor, 'vendor'), review({ buyerName: 'Me' }))); checks++; // own shop
    await assertSucceeds(getDocs(collection(stranger, 'vendor_listings/vendor/reviews'))); checks++;
    await assertFails(getDocs(collection(anon, 'vendor_listings/vendor/reviews'))); checks++;
    await assertFails(deleteDoc(revRef(vendor, 'buyer'))); checks++; // vendor cannot remove a review
    await assertSucceeds(deleteDoc(revRef(buyer))); checks++;

    console.log(`market rules: ${checks} checks passed`);
  } catch (error) {
    console.error('market rules FAILED after', checks, 'checks');
    console.error(error);
    process.exitCode = 1;
  } finally {
    await env.cleanup();
  }
})();
