const {spawnSync} = require('node:child_process');
let failed = false;
for (const file of ['firestore_rules_test.cjs', 'community_rules_test.cjs', 'current_profile_rules_test.cjs']) {
  console.log('Running', file);
  const result = spawnSync(process.execPath, ['test/' + file], {stdio: 'inherit'});
  if (result.status !== 0) failed = true;
}
process.exitCode = failed ? 1 : 0;
