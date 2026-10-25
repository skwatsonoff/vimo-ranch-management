// Run with the demo-vimo emulator only. Never targets a production project.
// Products and Mercari-style orders: who may write what, and every step.
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc, deleteDoc, collection, query, where, getDocs, writeBatch, increment, serverTimestamp} = require('firebase/firestore');
const fs = require('node:fs');

(async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-vimo', firestore: {host: '127.0.0.1', port: 8088, rules: fs.readFileSync('firestore.rules', 'utf8')}});
  let checks = 0;
  try {
    await env.clearFirestore();
    const seller = env.authenticatedContext('seller').firestore();
    const buyer = env.authenticatedContext('buyer').firestore();
    const other = env.authenticatedContext('other').firestore();
    const anon = env.unauthenticatedContext().firestore();
    const jpeg = 'data:image/jpeg;base64,' + 'A'.repeat(400);
    const product = (over = {}) => ({
      sellerUid: 'seller', sellerName: 'Selvi', title: 'A2 Ghee 500 ml', description: 'Fresh', features: ['Hand made'],
      category: 'ghee', condition: 'new', brand: '', tags: ['a2'], searchTerms: ['a2', 'ghee'],
      price: 450, mrp: 500, unit: 'pack', unitSize: '500 ml', stock: 3, sku: '', weightGrams: 520,
      origin: 'India', manufacturer: '', gstPercent: 5, hsn: '0405',
      delivery: {methods: ['pickup', 'courier'], payer: 'buyer', fee: 40, days: '2-3', shipsFrom: 'Salem'},
      returns: 'none', cover: jpeg, photoCount: 1, status: 'active',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over,
    });
    const pRef = (db) => doc(db, 'shop_products/p1');

    // --- Products ---
    await assertFails(setDoc(pRef(anon), product())); checks++;
    await assertFails(setDoc(pRef(buyer), product())); checks++; // someone else's name on it
    await assertFails(setDoc(pRef(seller), product({mrp: 400}))); checks++; // MRP below price
    await assertFails(setDoc(pRef(seller), product({tags: ['a', 'b', 'c', 'd', 'e', 'f']}))); checks++; // 5 tags at most
    await assertFails(setDoc(pRef(seller), product({cover: 'http://x/y.jpg'}))); checks++;
    await assertFails(setDoc(pRef(seller), product({photoCount: 6}))); checks++;
    await assertFails(setDoc(pRef(seller), product({hsn: '12'}))); checks++;
    await assertFails(setDoc(pRef(seller), product({delivery: {methods: [], payer: 'buyer', fee: 0, days: '1-2', shipsFrom: ''}}))); checks++;
    await assertFails(setDoc(pRef(seller), product({extra: true}))); checks++;
    const batch = writeBatch(seller);
    batch.set(pRef(seller), product());
    batch.set(doc(seller, 'shop_products/p1/photos/0'), {data: jpeg});
    await assertSucceeds(batch.commit()); checks++;
    await assertFails(setDoc(doc(seller, 'shop_products/p1/photos/5'), {data: jpeg})); checks++;
    await assertFails(setDoc(doc(buyer, 'shop_products/p1/photos/1'), {data: jpeg})); checks++;
    await assertSucceeds(getDoc(doc(buyer, 'shop_products/p1/photos/0'))); checks++;
    await assertSucceeds(getDocs(query(collection(buyer, 'shop_products'), where('status', '==', 'active'), where('searchTerms', 'array-contains', 'ghee')))); checks++;
    await assertFails(getDoc(pRef(anon))); checks++;
    await assertFails(updateDoc(pRef(buyer), {stock: 99, updatedAt: serverTimestamp()})); checks++;

    // --- Ordering ---
    const order = (over = {}) => ({
      productId: 'p1', sellerUid: 'seller', buyerUid: 'buyer', sellerName: 'Selvi', buyerName: 'Kumar',
      title: 'A2 Ghee 500 ml', cover: jpeg, unitPrice: 450, quantity: 2, deliveryMethod: 'courier', deliveryFee: 40,
      total: 940, payment: 'upi',
      address: {name: 'Kumar', phone: '9876543210', line: '12, Gandhi Street', city: 'Salem', pincode: '636001'},
      note: '', status: 'ordered', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over,
    });
    const oRef = (db, id = 'o1') => doc(db, 'shop_orders/' + id);
    await assertFails(setDoc(oRef(buyer), order({unitPrice: 1, total: 41}))); checks++; // not the product's price
    await assertFails(setDoc(oRef(buyer), order({deliveryFee: 0, total: 900}))); checks++; // fee belongs to buyer
    await assertFails(setDoc(oRef(buyer), order({total: 100}))); checks++;
    await assertFails(setDoc(oRef(buyer), order({quantity: 4, total: 1840}))); checks++; // more than stock
    await assertFails(setDoc(oRef(buyer), order({address: {}}))); checks++; // courier needs an address
    await assertFails(setDoc(oRef(buyer), order({address: {name: 'K', phone: '12', line: '12, Gandhi Street', city: 'Salem', pincode: '636001'}}))); checks++;
    await assertFails(setDoc(oRef(seller), order({buyerUid: 'seller'}))); checks++; // no buying your own
    await assertFails(setDoc(oRef(buyer), order({status: 'accepted'}))); checks++;
    await assertSucceeds(setDoc(oRef(buyer, 'pickup'), order({deliveryMethod: 'pickup', deliveryFee: 0, total: 900, address: {}, payment: 'cod'}))); checks++;
    await assertSucceeds(setDoc(oRef(buyer), order())); checks++;
    await assertSucceeds(getDoc(oRef(seller))); checks++;
    await assertFails(getDoc(oRef(other))); checks++;
    await assertSucceeds(getDocs(query(collection(buyer, 'shop_orders'), where('buyerUid', '==', 'buyer')))); checks++;
    await assertFails(getDocs(collection(other, 'shop_orders'))); checks++;

    // --- Steps, each by the right person only ---
    await assertFails(updateDoc(oRef(buyer), {status: 'accepted', acceptedAt: serverTimestamp(), sellerUpi: '', updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(oRef(seller), {status: 'shipped', shippedAt: serverTimestamp(), tracking: '', updatedAt: serverTimestamp()})); checks++; // skip a step
    await assertFails(updateDoc(oRef(seller), {status: 'accepted', acceptedAt: serverTimestamp(), sellerUpi: '', total: 1, updatedAt: serverTimestamp()})); checks++;
    const accept = writeBatch(seller);
    accept.update(oRef(seller), {status: 'accepted', acceptedAt: serverTimestamp(), sellerUpi: 'selvi@upi', updatedAt: serverTimestamp()});
    accept.update(pRef(seller), {stock: increment(-2), updatedAt: serverTimestamp()});
    await assertSucceeds(accept.commit()); checks++;
    await assertFails(updateDoc(oRef(buyer), {status: 'cancelled', cancelledAt: serverTimestamp(), cancelledBy: 'buyer', cancelReason: '', updatedAt: serverTimestamp()})); checks++; // too late for the buyer
    await assertSucceeds(updateDoc(oRef(seller), {status: 'shipped', shippedAt: serverTimestamp(), tracking: 'India Post EE1', updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(oRef(seller), {status: 'received', receivedAt: serverTimestamp(), buyerRating: {score: 'good', text: ''}, updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(oRef(buyer), {status: 'received', receivedAt: serverTimestamp(), buyerRating: {score: 'great', text: ''}, updatedAt: serverTimestamp()})); checks++;
    await assertSucceeds(updateDoc(oRef(buyer), {status: 'received', receivedAt: serverTimestamp(), buyerRating: {score: 'good', text: 'Lovely ghee'}, updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(oRef(buyer), {status: 'completed', completedAt: serverTimestamp(), sellerRating: {score: 'good', text: ''}, updatedAt: serverTimestamp()})); checks++;
    await assertSucceeds(updateDoc(oRef(seller), {status: 'completed', completedAt: serverTimestamp(), sellerRating: {score: 'good', text: 'Paid on time'}, updatedAt: serverTimestamp()})); checks++;
    await assertFails(deleteDoc(oRef(seller))); checks++;

    // Buyer can cancel before acceptance; seller after acceptance too.
    await assertSucceeds(updateDoc(oRef(buyer, 'pickup'), {status: 'cancelled', cancelledAt: serverTimestamp(), cancelledBy: 'buyer', cancelReason: 'Changed my mind', updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(oRef(buyer, 'pickup'), {status: 'ordered', updatedAt: serverTimestamp()})); checks++;

    // --- Order messages: the two parties only ---
    await assertSucceeds(setDoc(doc(buyer, 'shop_orders/o1/messages/m1'), {senderUid: 'buyer', text: 'Thanks!', createdAt: serverTimestamp()})); checks++;
    await assertFails(setDoc(doc(buyer, 'shop_orders/o1/messages/m2'), {senderUid: 'seller', text: 'Spoof', createdAt: serverTimestamp()})); checks++;
    await assertFails(setDoc(doc(other, 'shop_orders/o1/messages/m3'), {senderUid: 'other', text: 'Hi', createdAt: serverTimestamp()})); checks++;
    await assertSucceeds(getDoc(doc(seller, 'shop_orders/o1/messages/m1'))); checks++;
    await assertFails(getDoc(doc(other, 'shop_orders/o1/messages/m1'))); checks++;

    // Owner deletes the product with its photos.
    const remove = writeBatch(seller);
    remove.delete(doc(seller, 'shop_products/p1/photos/0'));
    remove.delete(pRef(seller));
    await assertFails(deleteDoc(pRef(buyer))); checks++;
    await assertSucceeds(remove.commit()); checks++;
    console.log(`Shop and order rules: ${checks} checks passed`);
  } catch (e) {
    console.error(e);
    process.exitCode = 1;
  } finally {
    await env.cleanup();
  }
})();
