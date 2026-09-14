// Run with the demo-vimo emulator only. Never targets a production project.
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc, collection, query, where, getDocs, Timestamp, serverTimestamp} = require('firebase/firestore');
const fs = require('node:fs');
(async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-vimo', firestore: {host: '127.0.0.1', port: 8088, rules: fs.readFileSync('firestore.rules', 'utf8')}});
  try {
    const a = env.authenticatedContext('alice').firestore();
    const b = env.authenticatedContext('bob').firestore();
    const c = env.authenticatedContext('outsider').firestore();
    await env.withSecurityRulesDisabled(async ctx => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/alice'), {username: 'alice'});
      await setDoc(doc(db, 'profiles/alice'), {username: 'alice', shareRanch: true, ranchId: 'farm', updatedAt: Timestamp.now()});
      await setDoc(doc(db, 'profiles/bob'), {username: 'bob', updatedAt: Timestamp.now()});
      // Existing approved legacy members need not have newer status flags.
      await setDoc(doc(db, 'ranches/farm/members/alice'), {role: 'Admin'});
      await setDoc(doc(db, 'ranches/farm/milk_records/milk'), {quantity: 3});
    });
    await assertSucceeds(getDoc(doc(a, 'ranches/farm/milk_records/milk')));
    const future = Timestamp.fromMillis(Date.now() + 3600000);
    await assertSucceeds(setDoc(doc(a, 'social_posts/scheduled'), {authorUid: 'alice', authorUsername: 'alice', authorName: 'Alice', ranchId: '', text: 'Scheduled calf photo', photo: '', voice: '', voiceSeconds: 0, tile: false, createdAt: future}));
    await assertSucceeds(getDoc(doc(a, 'social_posts/scheduled')));
    await assertFails(getDoc(doc(b, 'social_posts/scheduled')));
    await assertSucceeds(getDocs(query(collection(b, 'social_posts'), where('createdAt', '<=', Timestamp.now()))));
    await assertFails(updateDoc(doc(b, 'social_posts/scheduled'), {createdAt: future}));
    await assertFails(updateDoc(doc(a, 'social_posts/scheduled'), {authorUid: 'bob'}));
    await assertSucceeds(setDoc(doc(a, 'direct_chats/alice_bob'), {participants: ['alice', 'bob']}));
    await assertSucceeds(setDoc(doc(a, 'direct_chats/alice_bob/messages/one'), {senderUid: 'alice', text: 'Hello', createdAt: serverTimestamp()}));
    await assertSucceeds(getDoc(doc(b, 'direct_chats/alice_bob/messages/one')));
    await assertFails(getDoc(doc(c, 'direct_chats/alice_bob/messages/one')));
    await assertFails(updateDoc(doc(a, 'direct_chats/alice_bob'), {participants: ['alice', 'outsider']}));
    await assertFails(setDoc(doc(b, 'direct_chats/alice_bob/messages/forged'), {senderUid: 'alice', text: 'Forged', createdAt: serverTimestamp()}));
    await assertSucceeds(setDoc(doc(a, 'profiles/alice/contacts/bob'), {category: 'personal', createdAt: serverTimestamp()}));
    await assertFails(getDoc(doc(b, 'profiles/alice/contacts/bob')));
    await assertSucceeds(setDoc(doc(a, 'profiles/alice/cows/cow'), {name: 'Lakshmi', cowId: 'C1', breed: 'Jersey', photo: ''}));
    await assertFails(setDoc(doc(a, 'profiles/alice/cows/leak'), {name: 'Lakshmi', cowId: 'C1', breed: 'Jersey', photo: '', milkIncome: 300}));
    await assertSucceeds(getDoc(doc(b, 'profiles/alice/cows/cow')));
    await assertSucceeds(updateDoc(doc(a, 'profiles/alice'), {shareRanch: false, updatedAt: serverTimestamp()}));
    await assertFails(getDoc(doc(b, 'profiles/alice/cows/cow')));
    console.log('20 community security checks passed');
  } finally { await env.cleanup(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
