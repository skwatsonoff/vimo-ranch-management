const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,writeBatch,serverTimestamp,runTransaction} = require('firebase/firestore');
const fs = require('node:fs');
(async()=>{
 const env=await initializeTestEnvironment({projectId:'demo-vimo',firestore:{host:'127.0.0.1',port:8088,rules:fs.readFileSync('firestore.rules','utf8')}});
 let checks=0;
 try {
  await env.clearFirestore();
  const a=env.authenticatedContext('profile-a').firestore(), b=env.authenticatedContext('profile-b').firestore();
  async function claim(db,uid,name) {
   return runTransaction(db,async tx=>{
    await tx.get(doc(db,'users',uid)); await tx.get(doc(db,'usernames',name));
    tx.set(doc(db,'users',uid),{username:name,usernameChangedAt:serverTimestamp()});
    tx.set(doc(db,'usernames',name),{uid,claimedAt:serverTimestamp()});
    tx.set(doc(db,'profiles',uid),{username:name,updatedAt:serverTimestamp()});
   });
  }
  await assertSucceeds(claim(a,'profile-a','profile_alpha')); checks++;
  await assertSucceeds(claim(b,'profile-b','profile_beta')); checks++;
  await assertFails(claim(b,'profile-b','profile_alpha')); checks++;
  await assertFails(claim(a,'profile-a','profile_new')); checks++;
  const profile={username:'profile_alpha',bio:'Dairy farmer',photo:'',link:'https://example.com',updatedAt:serverTimestamp()};
  await assertSucceeds(setDoc(doc(a,'profiles/profile-a'),profile)); checks++;
  await assertSucceeds(getDoc(doc(b,'profiles/profile-a'))); checks++;
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'profiles/profile-a'))); checks++;
  await assertFails(setDoc(doc(b,'profiles/profile-a'),profile)); checks++;
  await assertFails(setDoc(doc(a,'profiles/profile-a'),{...profile,username:'profile_beta'})); checks++;
  await assertFails(setDoc(doc(a,'profiles/profile-a'),{...profile,link:'javascript:alert(1)'})); checks++;
  await assertFails(setDoc(doc(a,'profiles/profile-a'),{...profile,bio:'a'.repeat(161)})); checks++;
  await assertSucceeds(setDoc(doc(a,'profiles/profile-a'),{...profile,link:''})); checks++;
  await assertFails(setDoc(doc(a,'profiles/profile-b/followers/profile-a'),{createdAt:serverTimestamp()})); checks++;
  const follow=writeBatch(a);
  follow.set(doc(a,'profiles/profile-b/followers/profile-a'),{createdAt:serverTimestamp()});
  follow.set(doc(a,'profiles/profile-a/following/profile-b'),{createdAt:serverTimestamp()});
  await assertSucceeds(follow.commit()); checks++;
  const forge=writeBatch(b);
  forge.set(doc(b,'profiles/profile-a/followers/profile-a'),{createdAt:serverTimestamp()});
  forge.set(doc(b,'profiles/profile-a/following/profile-a'),{createdAt:serverTimestamp()});
  await assertFails(forge.commit()); checks++;
  const unfollow=writeBatch(a);
  unfollow.delete(doc(a,'profiles/profile-b/followers/profile-a'));
  unfollow.delete(doc(a,'profiles/profile-a/following/profile-b'));
  await assertSucceeds(unfollow.commit()); checks++;
  // Sign-up keeps the mobile number private in the account document.
  await assertSucceeds(setDoc(doc(a,'users/profile-a'),{fullName:'Alpha',phone:'9876543210',place:'Madurai'},{merge:true})); checks++;
  await assertFails(getDoc(doc(b,'users/profile-a'))); checks++;
  // Shared animal cards hold only a photo and are readable by signed-in people.
  const jpeg='data:image/jpeg;base64,'+'A'.repeat(64);
  const card={ownerUid:'profile-a',kind:'animal',photo:jpeg,photoUrl:'',createdAt:serverTimestamp()};
  await assertSucceeds(setDoc(doc(a,'shared_cards/card-1'),card)); checks++;
  await assertSucceeds(getDoc(doc(b,'shared_cards/card-1'))); checks++;
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'shared_cards/card-1'))); checks++;
  await assertFails(setDoc(doc(b,'shared_cards/card-2'),card)); checks++;
  await assertFails(setDoc(doc(a,'shared_cards/card-3'),{...card,ranchId:'secret'})); checks++;
  await assertFails(setDoc(doc(a,'shared_cards/card-4'),{...card,photo:'data:image/png;base64,AAAA'})); checks++;
  await assertFails(setDoc(doc(a,'shared_cards/card-1'),{...card,kind:'animal'})); checks++;
  console.log(`${checks} current profile/username rules checks passed`);
 } finally {await env.cleanup();}
})().catch(e=>{console.error(e);process.exitCode=1;});
