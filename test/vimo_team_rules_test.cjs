// Run with the demo-vimo emulator only. Never targets a production project.
// VIMO Team: reports open one chat and the orders between two people to the
// team only; support threads; Market blocks; only the team acts.
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, getDocs, updateDoc, collection, query, where, writeBatch, serverTimestamp, deleteField, Timestamp} = require('firebase/firestore');
const fs = require('node:fs');

(async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-vimo', firestore: {host: '127.0.0.1', port: 8088, rules: fs.readFileSync('firestore.rules', 'utf8')}});
  let checks = 0;
  try {
    await env.clearFirestore();
    const buyer = env.authenticatedContext('buyer').firestore();
    const seller = env.authenticatedContext('seller').firestore();
    const other = env.authenticatedContext('other').firestore();
    const team = env.authenticatedContext('team').firestore();
    const jpeg = 'data:image/jpeg;base64,' + 'A'.repeat(400);
    const product = {
      sellerUid: 'seller', sellerName: 'Selvi', title: 'Ghee', description: '', features: [],
      category: 'ghee', condition: 'new', brand: '', tags: [], searchTerms: ['ghee'],
      price: 450, mrp: 0, unit: 'pack', unitSize: '', stock: 3, maxPerOrder: 1, sku: '', weightGrams: 0,
      origin: 'India', manufacturer: '', gstPercent: 0, hsn: '',
      delivery: {methods: ['pickup'], payer: 'buyer', fee: 0, days: '1-2', shipsFrom: 'Salem'},
      returns: 'none', cover: jpeg, photoCount: 1, status: 'active',
      createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
    };
    const listing = {name: 'Selvi', kind: 'vendor', gridLat: 6541, gridLng: 40135, cell: '261:1605', price: 60, morning: {start: '05:30', end: '08:00'}, evening: {}, active: true, holiday: false, onRide: false, updatedAt: serverTimestamp()};
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'vimo_admins/team'), {name: 'VIMO'});
      await setDoc(doc(db, 'direct_chats/buyer_seller'), {participants: ['buyer', 'seller']});
      await setDoc(doc(db, 'direct_chats/buyer_seller/messages/m1'), {senderUid: 'seller', text: 'Pay first', createdAt: new Date()});
      await setDoc(doc(db, 'direct_chats/buyer_other/messages/x'), {senderUid: 'other', text: 'Private', createdAt: new Date()});
      await setDoc(doc(db, 'direct_chats/buyer_other'), {participants: ['buyer', 'other']});
      await setDoc(doc(db, 'shop_products/p1'), product);
      await setDoc(doc(db, 'shop_orders/o1'), {productId: 'p1', sellerUid: 'seller', buyerUid: 'buyer', status: 'shipped', title: 'Ghee'});
      await setDoc(doc(db, 'shop_orders/o1/messages/a'), {senderUid: 'buyer', text: 'Where is it?', createdAt: new Date()});
      await setDoc(doc(db, 'shop_orders/o2'), {productId: 'p1', sellerUid: 'seller', buyerUid: 'other', status: 'ordered', title: 'Ghee'});
    });

    // Before any report the team sees nothing private.
    await assertFails(getDoc(doc(team, 'shop_orders/o1'))); checks++;
    await assertFails(getDocs(collection(team, 'direct_chats/buyer_seller/messages'))); checks++;
    await assertSucceeds(getDoc(doc(team, 'vimo_admins/team'))); checks++;
    await assertFails(getDoc(doc(buyer, 'vimo_admins/team'))); checks++;
    await assertFails(setDoc(doc(buyer, 'vimo_admins/buyer'), {name: 'me'})); checks++;

    const report = (over = {}) => ({
      reporterUid: 'buyer', reporterName: 'Kumar', againstUid: 'seller', againstName: 'Selvi',
      topic: 'order', reason: 'not_received', text: 'Paid by UPI, nothing came for ten days.',
      orderId: 'o1', chatId: 'buyer_seller', orderIds: ['o1'], status: 'open',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over,
    });
    await assertFails(setDoc(doc(buyer, 'vimo_reports/r0'), report({reporterUid: 'seller'}))); checks++;
    await assertFails(setDoc(doc(buyer, 'vimo_reports/r0'), report({againstUid: 'buyer'}))); checks++;
    await assertFails(setDoc(doc(buyer, 'vimo_reports/r0'), report({text: 'bad'}))); checks++;
    await assertFails(setDoc(doc(buyer, 'vimo_reports/r0'), report({status: 'resolved'}))); checks++;
    await assertFails(setDoc(doc(buyer, 'vimo_reports/r0'), report({chatId: 'buyer_other'}))); checks++;

    // A stranger cannot open someone else's chat or order to the team.
    const sneak = writeBatch(other);
    sneak.set(doc(other, 'vimo_reports/r9'), report({reporterUid: 'other', reporterName: 'X', chatId: '', orderIds: []}));
    sneak.set(doc(other, 'vimo_reported_chats/buyer_seller'), {reportId: 'r9', at: serverTimestamp()});
    await assertFails(sneak.commit()); checks++;
    const sneak2 = writeBatch(other);
    sneak2.set(doc(other, 'vimo_reports/r9'), report({reporterUid: 'other', reporterName: 'X', chatId: '', orderIds: []}));
    sneak2.set(doc(other, 'vimo_reported_orders/o1'), {reportId: 'r9', at: serverTimestamp()});
    await assertFails(sneak2.commit()); checks++;
    // Opening needs a real report in the same step.
    await assertFails(setDoc(doc(buyer, 'vimo_reported_orders/o1'), {reportId: 'nothing', at: serverTimestamp()})); checks++;

    const send = writeBatch(buyer);
    send.set(doc(buyer, 'vimo_reports/r1'), report());
    send.set(doc(buyer, 'vimo_reported_chats/buyer_seller'), {reportId: 'r1', at: serverTimestamp()});
    send.set(doc(buyer, 'vimo_reported_orders/o1'), {reportId: 'r1', at: serverTimestamp()});
    await assertSucceeds(send.commit()); checks++;

    // Who sees the report.
    await assertSucceeds(getDoc(doc(buyer, 'vimo_reports/r1'))); checks++;
    await assertFails(getDoc(doc(seller, 'vimo_reports/r1'))); checks++; // not told who reported
    await assertSucceeds(getDocs(query(collection(buyer, 'vimo_reports'), where('reporterUid', '==', 'buyer')))); checks++;
    await assertFails(getDocs(collection(buyer, 'vimo_reports'))); checks++;
    await assertSucceeds(getDocs(collection(team, 'vimo_reports'))); checks++;
    await assertFails(updateDoc(doc(buyer, 'vimo_reports/r1'), {status: 'resolved', updatedAt: serverTimestamp()})); checks++;

    // Now the team reads that chat and order, and nothing else.
    await assertSucceeds(getDocs(collection(team, 'direct_chats/buyer_seller/messages'))); checks++;
    await assertSucceeds(getDoc(doc(team, 'shop_orders/o1'))); checks++;
    await assertSucceeds(getDocs(collection(team, 'shop_orders/o1/messages'))); checks++;
    await assertFails(getDocs(collection(team, 'direct_chats/buyer_other/messages'))); checks++;
    await assertFails(getDoc(doc(team, 'shop_orders/o2'))); checks++;
    await assertFails(getDocs(collection(other, 'direct_chats/buyer_seller/messages'))); checks++;

    // The team handles it.
    await assertFails(updateDoc(doc(team, 'vimo_reports/r1'), {status: 'closed', updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(doc(team, 'vimo_reports/r1'), {text: 'changed', updatedAt: serverTimestamp()})); checks++;
    await assertSucceeds(updateDoc(doc(team, 'vimo_reports/r1'), {status: 'reviewing', handledBy: 'team', updatedAt: serverTimestamp()})); checks++;
    const end = {status: 'cancelled', cancelledAt: serverTimestamp(), cancelledBy: 'vimo', cancelReason: 'Seller did not send it', cancelRequest: deleteField(), updatedAt: serverTimestamp()};
    await assertFails(updateDoc(doc(team, 'shop_orders/o2'), end)); checks++; // not reported
    await assertFails(updateDoc(doc(buyer, 'shop_orders/o1'), end)); checks++; // only the team
    await assertSucceeds(updateDoc(doc(team, 'shop_orders/o1'), end)); checks++;
    await assertFails(updateDoc(doc(team, 'shop_products/p1'), {status: 'active', updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(doc(seller, 'shop_products/p1'), {pausedByTeam: true, updatedAt: serverTimestamp()})); checks++; // only the team marks it
    await assertSucceeds(updateDoc(doc(team, 'shop_products/p1'), {status: 'paused', pausedByTeam: true, updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(doc(team, 'shop_products/p1'), {price: 1, updatedAt: serverTimestamp()})); checks++;
    // The seller cannot show it again, or clear the mark, until the team allows it.
    await assertFails(updateDoc(doc(seller, 'shop_products/p1'), {status: 'active', updatedAt: serverTimestamp()})); checks++;
    await assertFails(updateDoc(doc(seller, 'shop_products/p1'), {status: 'active', pausedByTeam: false, updatedAt: serverTimestamp()})); checks++;
    await assertSucceeds(updateDoc(doc(seller, 'shop_products/p1'), {title: 'A2 Ghee', updatedAt: serverTimestamp()})); checks++; // other edits are fine
    await assertSucceeds(updateDoc(doc(team, 'shop_products/p1'), {pausedByTeam: false, updatedAt: serverTimestamp()})); checks++;
    await assertSucceeds(updateDoc(doc(seller, 'shop_products/p1'), {status: 'active', updatedAt: serverTimestamp()})); checks++;
    await assertFails(setDoc(doc(seller, 'shop_products/p9'), {...product, pausedByTeam: false, createdAt: serverTimestamp(), updatedAt: serverTimestamp()})); checks++;

    // Support threads: each person and the team only.
    const msg = (from, senderUid, text = 'Hello') => ({from, senderUid, text, reportId: 'r1', createdAt: serverTimestamp()});
    const thread = (lastFrom) => ({name: 'Kumar', lastText: 'Hello', lastFrom, updatedAt: serverTimestamp()});
    const userSend = writeBatch(buyer);
    userSend.set(doc(buyer, 'vimo_support/buyer/messages/1'), msg('user', 'buyer'));
    userSend.set(doc(buyer, 'vimo_support/buyer'), thread('user'));
    await assertSucceeds(userSend.commit()); checks++;
    await assertFails(setDoc(doc(buyer, 'vimo_support/buyer/messages/2'), msg('team', 'buyer'))); checks++; // pretending to be the team
    await assertFails(setDoc(doc(buyer, 'vimo_support/buyer'), thread('team'))); checks++;
    await assertFails(setDoc(doc(other, 'vimo_support/buyer/messages/3'), msg('user', 'other'))); checks++;
    await assertFails(getDoc(doc(other, 'vimo_support/buyer'))); checks++;
    await assertFails(getDocs(collection(seller, 'vimo_support/buyer/messages'))); checks++;
    const teamSend = writeBatch(team);
    teamSend.set(doc(team, 'vimo_support/seller/messages/1'), msg('team', 'team', 'Please send the order.'));
    teamSend.set(doc(team, 'vimo_support/seller'), {...thread('team'), name: 'Selvi'});
    await assertSucceeds(teamSend.commit()); checks++;
    await assertSucceeds(getDocs(collection(seller, 'vimo_support/seller/messages'))); checks++;
    await assertSucceeds(getDocs(collection(team, 'vimo_support'))); checks++;

    // Market block: only the team sets it; it stops selling and buying.
    const block = {market: 'blocked', warnings: 1, reason: 'Did not send paid orders', by: 'team', updatedAt: serverTimestamp()};
    await assertFails(setDoc(doc(seller, 'vimo_sanctions/seller'), {...block, market: 'ok', by: 'seller'})); checks++;
    await assertFails(setDoc(doc(team, 'vimo_sanctions/seller'), {...block, by: 'someone'})); checks++;
    await assertSucceeds(setDoc(doc(team, 'vimo_sanctions/seller'), block)); checks++;
    await assertSucceeds(getDoc(doc(seller, 'vimo_sanctions/seller'))); checks++;
    await assertFails(getDoc(doc(buyer, 'vimo_sanctions/seller'))); checks++;
    // Valid writes that fail only because of the block…
    await assertFails(setDoc(doc(seller, 'vendor_listings/seller'), listing)); checks++;
    await assertFails(updateDoc(doc(seller, 'shop_products/p1'), {stock: 2, updatedAt: serverTimestamp()})); checks++;
    await assertSucceeds(setDoc(doc(team, 'vimo_sanctions/seller'), {...block, market: 'ok', reason: ''})); checks++;
    // …and go through once Market is open again.
    await assertSucceeds(setDoc(doc(seller, 'vendor_listings/seller'), listing)); checks++;
    await assertSucceeds(updateDoc(doc(seller, 'shop_products/p1'), {stock: 2, updatedAt: serverTimestamp()})); checks++;

    console.log(`VIMO Team rules: ${checks} checks passed`);
  } catch (e) {
    console.error(e);
    process.exitCode = 1;
  } finally {
    await env.cleanup();
  }
})();
