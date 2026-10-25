// Run with the demo-vimo emulator only. Never targets a production project.
// Likes, offers (accept, then buy one at that price within 24 hours) and
// public questions on Market items.
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, getDocs, updateDoc, deleteDoc, collection, query, where, writeBatch, serverTimestamp, Timestamp} = require('firebase/firestore');
const fs = require('node:fs');

(async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-vimo', firestore: {host: '127.0.0.1', port: 8088, rules: fs.readFileSync('firestore.rules', 'utf8')}});
  let checks = 0;
  try {
    await env.clearFirestore();
    const seller = env.authenticatedContext('seller').firestore();
    const buyer = env.authenticatedContext('buyer').firestore();
    const other = env.authenticatedContext('other').firestore();
    const jpeg = 'data:image/jpeg;base64,' + 'A'.repeat(400);
    const product = {
      sellerUid: 'seller', sellerName: 'Selvi', title: 'Jersey cow', description: '', features: [],
      category: 'animals', condition: 'good', brand: '', tags: [], searchTerms: ['cow'],
      price: 40000, mrp: 0, unit: 'piece', unitSize: '', stock: 1, maxPerOrder: 1, sku: '', weightGrams: 0,
      origin: 'India', manufacturer: '', gstPercent: 0, hsn: '',
      delivery: {methods: ['pickup'], payer: 'buyer', fee: 0, days: '1-2', shipsFrom: 'Salem'},
      returns: 'none', cover: jpeg, photoCount: 1, status: 'active',
      createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
    };
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'shop_products/cow'), product);
    });

    // --- Likes ---
    const like = (over = {}) => ({uid: 'buyer', productId: 'cow', title: 'Jersey cow', price: 40000, createdAt: serverTimestamp(), ...over});
    await assertFails(setDoc(doc(buyer, 'shop_likes/other_cow'), like({uid: 'other'}))); checks++;
    await assertFails(setDoc(doc(buyer, 'shop_likes/buyer_nothing'), like({productId: 'nothing'}))); checks++;
    await assertSucceeds(setDoc(doc(buyer, 'shop_likes/buyer_cow'), like())); checks++;
    await assertSucceeds(getDocs(query(collection(other, 'shop_likes'), where('productId', '==', 'cow')))); checks++;
    await assertFails(deleteDoc(doc(other, 'shop_likes/buyer_cow'))); checks++;
    await assertSucceeds(deleteDoc(doc(buyer, 'shop_likes/buyer_cow'))); checks++;

    // --- Offers ---
    const offer = (over = {}) => ({productId: 'cow', sellerUid: 'seller', buyerUid: 'buyer', buyerName: 'Kumar', title: 'Jersey cow', listPrice: 40000, price: 35000, status: 'pending', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over});
    const oRef = (db) => doc(db, 'shop_offers/cow_buyer');
    await assertFails(setDoc(oRef(buyer), offer({price: 19000}))); checks++; // below half
    await assertFails(setDoc(oRef(buyer), offer({price: 40000}))); checks++; // not an offer
    await assertFails(setDoc(oRef(buyer), offer({status: 'accepted'}))); checks++;
    await assertFails(setDoc(doc(seller, 'shop_offers/cow_seller'), offer({buyerUid: 'seller'}))); checks++; // own item
    await assertFails(setDoc(doc(other, 'shop_offers/cow_buyer'), offer({buyerUid: 'other'}))); checks++;
    await assertSucceeds(setDoc(oRef(buyer), offer())); checks++;
    await assertFails(setDoc(oRef(buyer), offer({price: 30000}))); checks++; // one pending at a time
    await assertFails(getDoc(oRef(other))); checks++;
    await assertSucceeds(getDocs(query(collection(seller, 'shop_offers'), where('sellerUid', '==', 'seller'), where('productId', '==', 'cow')))); checks++;
    await assertFails(updateDoc(oRef(buyer), {status: 'accepted', acceptedAt: serverTimestamp(), updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(oRef(seller), {status: 'accepted', acceptedAt: serverTimestamp(), price: 39000, updatedAt: serverTimestamp()})); checks++;
    await assertSucceeds(updateDoc(oRef(seller), {status: 'accepted', acceptedAt: serverTimestamp(), updatedAt: serverTimestamp()})); checks++;

    // Buying at the offer: one item, at that price, using the offer up.
    const order = (over = {}) => ({
      productId: 'cow', sellerUid: 'seller', buyerUid: 'buyer', sellerName: 'Selvi', buyerName: 'Kumar',
      title: 'Jersey cow', cover: jpeg, unitPrice: 35000, quantity: 1, deliveryMethod: 'pickup', deliveryFee: 0,
      total: 35000, payment: 'cod', address: {}, note: '', offerId: 'cow_buyer', status: 'ordered',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over,
    });
    await assertFails(setDoc(doc(buyer, 'shop_orders/a'), order())); checks++; // offer must be used in the same step
    const cheat = writeBatch(buyer);
    cheat.set(doc(buyer, 'shop_orders/b'), order({unitPrice: 30000, total: 30000}));
    cheat.update(oRef(buyer), {status: 'used', orderId: 'b', updatedAt: serverTimestamp()});
    await assertFails(cheat.commit()); checks++;
    await assertFails(setDoc(doc(other, 'shop_orders/c'), order({buyerUid: 'other', buyerName: 'X'}))); checks++; // someone else's offer
    const buy = writeBatch(buyer);
    buy.set(doc(buyer, 'shop_orders/d'), order());
    buy.update(oRef(buyer), {status: 'used', orderId: 'd', updatedAt: serverTimestamp()});
    await assertSucceeds(buy.commit()); checks++;
    await assertFails(setDoc(doc(buyer, 'shop_orders/e'), order())); checks++; // used once only
    // Without an offer the list price applies.
    const plain = order({unitPrice: 35000, total: 35000});
    delete plain.offerId;
    await assertFails(setDoc(doc(buyer, 'shop_orders/g'), plain)); checks++;

    // An accepted offer older than 24 hours no longer buys.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'shop_offers/cow_other'), offer({buyerUid: 'other', buyerName: 'X', status: 'accepted', acceptedAt: Timestamp.fromMillis(Date.now() - 25 * 3600 * 1000)}));
    });
    const late = writeBatch(other);
    late.set(doc(other, 'shop_orders/h'), order({buyerUid: 'other', buyerName: 'X', offerId: 'cow_other'}));
    late.update(doc(other, 'shop_offers/cow_other'), {status: 'used', orderId: 'h', updatedAt: serverTimestamp()});
    await assertFails(late.commit()); checks++;

    // --- Questions ---
    const q = (over = {}) => ({productId: 'cow', sellerUid: 'seller', title: 'Jersey cow', uid: 'other', name: 'Ravi', text: 'How much milk a day?', answer: '', createdAt: serverTimestamp(), ...over});
    await assertFails(setDoc(doc(other, 'shop_questions/q0'), q({uid: 'buyer'}))); checks++;
    await assertFails(setDoc(doc(other, 'shop_questions/q0'), q({answer: 'Lots'}))); checks++;
    await assertFails(setDoc(doc(other, 'shop_questions/q0'), q({sellerUid: 'other'}))); checks++;
    await assertSucceeds(setDoc(doc(other, 'shop_questions/q1'), q())); checks++;
    await assertSucceeds(getDocs(query(collection(buyer, 'shop_questions'), where('productId', '==', 'cow')))); checks++;
    await assertFails(updateDoc(doc(other, 'shop_questions/q1'), {answer: 'Self answer', answeredAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(doc(seller, 'shop_questions/q1'), {text: 'changed'})); checks++;
    await assertSucceeds(updateDoc(doc(seller, 'shop_questions/q1'), {answer: '12 litres', answeredAt: serverTimestamp()})); checks++;
    await assertFails(deleteDoc(doc(buyer, 'shop_questions/q1'))); checks++;
    await assertSucceeds(setDoc(doc(buyer, 'shop_questions/q2'), q({uid: 'buyer', name: 'Kumar'}))); checks++;
    await assertSucceeds(deleteDoc(doc(seller, 'shop_questions/q2'))); checks++;
    await assertSucceeds(deleteDoc(doc(other, 'shop_questions/q1'))); checks++;

    console.log(`Likes, offers and questions rules: ${checks} checks passed`);
  } catch (e) {
    console.error(e);
    process.exitCode = 1;
  } finally {
    await env.cleanup();
  }
})();
