const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const configuration = {
  VIMO_ACCESS_CODE: 'a'.repeat(64),
  GEMINI_PROJECT_ID: 'vimo-free-test',
  GEMINI_API_KEY: 'fixture',
};
let billing = false;
let quota = false;
let geminiCalls = 0;
const reply = (data, status = 200) => ({
  getResponseCode: () => status,
  getContentText: () => JSON.stringify(data),
});
const runtime = vm.createContext({
  PropertiesService: {getScriptProperties: () => ({getProperty: key => configuration[key]})},
  ScriptApp: {getOAuthToken: () => 'fixture'},
  ContentService: {
    MimeType: {JSON: 'json'},
    createTextOutput: payload => ({setMimeType: () => JSON.parse(payload)}),
  },
  UrlFetchApp: {fetch(url) {
    if (url.includes('apikeys.googleapis.com')) {
      return reply({parent: 'projects/123/locations/global', name: 'projects/123/locations/global/keys/fixture'});
    }
    if (url.includes('cloudresourcemanager.googleapis.com')) {
      return reply({projectId: 'vimo-free-test'});
    }
    if (url.includes('cloudbilling.googleapis.com')) {
      return reply({billingEnabled: billing});
    }
    if (url.endsWith(':generateContent')) {
      geminiCalls++;
      return quota
        ? reply({}, 429)
        : reply({candidates: [{content: {parts: [{text: '{"cowIndex":0,"litres":5}'}]}}]});
    }
    throw Error(url);
  }},
});
vm.runInContext(fs.readFileSync(require('node:path').join(__dirname, 'Code.gs'), 'utf8'), runtime);
const post = (over = {}) => runtime.doPost({postData: {contents: JSON.stringify({
  code: configuration.VIMO_ACCESS_CODE, scope: 'b'.repeat(64),
  op: 'milk', text: '5 லிட்டர் கண்மணி', cows: ['Kanmani'], ...over,
})}});

assert.deepEqual(post({code: 'x'.repeat(64)}), {error: 'access'});
billing = true;
assert.deepEqual(post(), {error: 'billing'});
assert.equal(geminiCalls, 0);
billing = false;
assert.deepEqual(post(), {cowIndex: 0, litres: 5});
quota = true;
assert.deepEqual(post(), {error: 'quota'});

let data;
const file = {
  getBlob: () => ({getDataAsString: () => data}),
  setContent: next => { data = next; },
};
const folder = {
  getFilesByName: () => ({hasNext: () => data !== undefined, next: () => file}),
  createFile: (_, next) => { data = next; },
};
const row = {
  key: 'text:butterfly 5 litres', kind: 'text', heard: 'butterfly 5 litres',
  meant: 'Kanmani 5 litres', changed: 1234, deleted: false,
};
assert.equal(runtime.syncLessons(folder, [row]).rows[0].meant, row.meant);
assert.equal(runtime.syncLessons(folder, [{...row, changed: 1235, deleted: true}]).rows[0].deleted, true);
assert.equal(runtime.syncLessons(folder, [row]).rows[0].deleted, true);
console.log('Drive merge, deletion, access checks, Gemini billing and quota checks passed.');
