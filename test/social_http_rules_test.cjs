// Real client-token REST requests; no production project or admin token.
const {initializeTestEnvironment} = require('@firebase/rules-unit-testing');
const {createMockUserToken} = require('@firebase/util');
const {doc,setDoc,Timestamp} = require('firebase/firestore');
const assert = require('node:assert/strict');
const fs = require('node:fs');
(async()=>{
 const projectId='demo-vimo-social-http';
 const env=await initializeTestEnvironment({projectId,firestore:{host:'127.0.0.1',port:8088,rules:fs.readFileSync('firestore.rules','utf8')}});
 try {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
   for(const [id,offset] of [['published',-60000],['scheduled',3600000]])
    await setDoc(doc(ctx.firestore(),'social_posts',id),{authorUid:'alice',text:id,createdAt:Timestamp.fromMillis(Date.now()+offset)});
  });
  async function query(uid,filters){
   const response=await fetch(`http://127.0.0.1:8088/v1/projects/${projectId}/databases/(default)/documents:runQuery`,{
    method:'POST',headers:{'Content-Type':'application/json',...(uid?{Authorization:`Bearer ${createMockUserToken({sub:uid},projectId)}`}:{})},
    body:JSON.stringify({structuredQuery:{from:[{collectionId:'social_posts'}],...(filters?{where:filters}:{}),orderBy:[{field:{fieldPath:'createdAt'},direction:'DESCENDING'}],limit:60}})
   });
   return {status:response.status,body:await response.json()};
  }
  const timeFilter=()=>({fieldFilter:{field:{fieldPath:'createdAt'},op:'LESS_THAN_OR_EQUAL',value:{timestampValue:new Date().toISOString()}}});
  const first=await query('bob',timeFilter());
  assert.equal(first.status,200); assert.deepEqual(first.body.filter(r=>r.document).map(r=>r.document.name.split('/').pop()),['published']);
  assert.equal((await query('bob',null)).status,403);
  assert.equal((await query(null,timeFilter())).status,403);
  const own=await query('alice',{fieldFilter:{field:{fieldPath:'authorUid'},op:'EQUAL',value:{stringValue:'alice'}}});
  assert.equal(own.status,200); assert.equal(own.body.filter(r=>r.document).length,2);
  // Repeat with a new boundary while the same user remains signed in.
  assert.equal((await query('bob',timeFilter())).status,200);
  console.log('7 HTTP feed security checks passed');
 } finally {await env.cleanup();}
})().catch(e=>{console.error(e);process.exitCode=1;});
