# Continue VIMO on the laptop

## Released — 2026-09-16 (supersedes all historical blockers below)

- PR #2 was merged into `codex/ranch-vendor-market-glass` as `ace79b3`.
  The laptop now checks out that branch. Additional sync correction: `2e65d34`.
- Production hosting, Firestore rules and indexes were deployed successfully to
  https://my-ranch-sync.web.app. The production build uses no emulator flags.
- Fresh production verification reproduced the SDK assertion after the first
  release, so reducing shell rebuilds alone was insufficient. The follow-up uses
  IndexedDB persistence and automatic transport detection, and stops resetting
  network/backoff state on every synchronization pass.
- After deploying the follow-up, the user's signed-in `myvimo` ranch progressed
  from three pending changes to `Synced`, `Pending Records 0`, and
  `Last Synced Today 18:10`. No new console errors/warnings were recorded while
  navigating profile/settings/sync and checking username availability.
- Production profile feed loaded successfully with `No posts yet`; follower
  counts resolved. The existing `skwatson` username lookup returned available,
  saved successfully, and the profile editor then displayed `@skwatson`.
- Release build passed; source analysis has no errors/warnings (two existing
  informational lints); all six sync coordinator checks passed again. Previous
  validation: 57 Flutter tests and 96 Firestore security checks passed, with
  GitHub CI successful on `94017bf` before merging.
- No fabricated posts, livestock, milk or financial records were added to the
  production account. Cross-account/offline record tests used the demo emulator.

The sections below retain the earlier investigation history; their release
blockers and old working-branch instructions are no longer current.

## Laptop verification — 2026-09-15 (supersedes blockers below)

- Reproduced the same Firestore 12.19.0 `ca9` / `b815` watch-stream crash in
  the user's production browser and the isolated integration app.
- The main shell no longer rebuilds for every sync status/queue write. This
  prevents repeated UI listener cancellation/recreation during synchronization.
  The repaired integration session completed profile, username and record writes
  without the previous SDK assertion.
- Time-bound social feeds now use authenticated REST runQuery requests every
  30 seconds. A reused Listen stream retained an earlier request.time and denied
  newer feed boundaries. Firebase user ID tokens still enforce Firestore rules;
  scheduled posts remain unreadable by others before their publication time.
- Split missing-post get permission from list authorization; tested the actual
  composer read-before-create transaction, owner queries, and anonymous denial.
- All 57 Flutter tests passed. Analysis has no errors or warnings (two existing
  informational lints in sync_core_checks.dart). The original 89 rules checks
  and seven additional real HTTP authorization checks passed locally.
- Browser verified: mobile Ranch Sell choices, separate Vendor navigation,
  storage detail entry point, profile layout and cow silhouette, username check
  and save, profile save, publishing and feed display, Personal/Business chat.
- Two isolated signed-in accounts share demo ranch `integration`: a saved ₹123
  expense appeared on the other device without manual sync. A ₹77 offline entry
  reached Firestore after reconnect; a fresh client displayed the ₹200 total.
- Production Firebase CLI login is available. Release build, GitHub publication,
  deployment and fresh production verification are the final steps in progress.

Local integration uses `--dart-define=VIMO_USE_EMULATORS=true` with project
`demo-vimo`, Auth on 9099 and Firestore on 8088. Never deploy that build or the
VIMO_PREVIEW_MODE build. Production builds omit both flags.

Repository: https://github.com/skwatsonoff/vimo-ranch-management
PR: https://github.com/skwatsonoff/vimo-ranch-management/pull/2
Working branch: `codex/sync-profile-community-fix`
Correct base: `codex/ranch-vendor-market-glass` (`402a6f450b835fc94a14ef04adee4f86dbb6c7fb`).
Do not restart from main: it is an older app. Do not overwrite unrelated local edits.
Production must keep the SAME URL: https://my-ranch-sync.web.app
Firebase project: `my-ranch-sync`. No production deploy has been performed.

## User instructions

Continue from this branch and finish the app. The user explicitly authorized the
code changes and publication. Do not repeat general permission questions. They
want concise Tamil responses, careful fixes, and no unnecessary repeated testing.
They are transferring execution to their laptop because Firebase authentication
and local browser verification are unavailable in the cloud environment.

## Requested behavior and implementation already on this branch

- Top-left home settings replaced with profile avatar. Profile contains lavender
  glass header, photo, followers/following, bio, WhatsApp/link, top-right settings,
  Post/Ranch/Vendor tabs, vertically stacked actual posts. Public cows and shop
  details are opt-in. Do not add fake example posts as real user data.
- Automatic sync after saved edits: bounded debounce, retry pending work,
  account/ranch-scoped snapshot guards, exact-revision acknowledgment, protected
  settings queue, realtime ranch listeners. Duplicate manual sync/upload and
  auto-sync disable controls removed. Status distinguishes connection failure
  from unsent rows. Private chat outbox is separate from ranch backups.
- Username checks normalize input and ignore stale responses, support prefilled
  names, distinguish Firebase errors, and reserve handles transactionally.
  Posting refreshes the actual server username. An empty-draft composer crash
  discovered by tests is fixed. These do not yet prove the reported LIVE
  username/posting/network problem is fixed.
- Personal chat has ranch group, members and manually added contacts; Business
  chat contains other social contacts. Private messages have durable outbox.
- Posts can be deleted or scheduled. Future createdAt controls visibility in
  Firestore rules; feed boundary refreshes every 30 seconds. Profile post query
  requires the index in firestore.indexes.json.
- Search people by username/name; search ranch name/ID and request to join without
  deleting the current ranch or its unsynced records.
- Ranch: Overview, Cows, Calves, Sell, Stock, Reports. Sell includes milk, cows,
  calves and manure. Ranch reports and their exports exclude vendor transactions.
- Vendor: Collect milk (households; Morning/Evening), Buy milk (bulk suppliers or
  shops), Sell milk (households/tea shops), Milk stock, Reports. Source details
  open when tapping milk storage or entries. Dedicated vendor CSV export.
- New vendor entries use stockScope `vendor_v2` and stock document
  `vendor_stock/vendor_milk`. New vendor transactions never consume ranch milk.
  RanchMilkBridge is no longer called. Historical records are retained; an admin
  initializes the vendor-only opening quantity once. Historical implicit ranch
  consumption remains accounted for. Review migration and update all old clients
  together with rules: old clients writing the mixed stock document are rejected.

## Verification and current concrete blocker

Completed on 2026-09-14:
- 57 Flutter tests passed (full suite, including the added Ranch Sell widget test).
- 6 standalone sync-core checks passed.
- Flutter analysis: no errors or warnings; informational style/test lints only.
- Release web build passed. Formatting and git diff checks passed.

Firestore tests MUST be finished before release:
- Local emulator could not start: Java 21 ClassFormatError in sun/misc/Unsafe.
- Added `.github/workflows/firestore-checks.yml`, which successfully starts the
  emulator in GitHub Actions using a demo project, without production credentials.
- First CI run FAILED during `test/firestore_rules_test.cjs` with permission-denied
  for a GET at firestore.rules line 172 (social_posts read rule). Earlier vendor
  checks reached this point; expected-denial logs are not necessarily failures.
  Failed run: https://github.com/skwatsonoff/vimo-ranch-management/actions/runs/34805005167
- Latest checkpoint adds failure check-count reporting and a runner that executes
  all three rules suites, so one failing suite no longer conceals the others.
  Check the newest PR Actions run for the precise failing assertion and fix the
  underlying rule/client issue. Do not weaken access controls to make tests pass.
- `CODEX_HANDOFF.md` supersedes the older blocked-emulator statement in
  CHANGE_REVIEW.md: cloud CI did start and exposed a real rules test failure.

Browser UI verification did not run: cloud browser refused localhost with
ERR_BLOCKED_BY_CLIENT. Verify mobile layouts on the laptop, especially profile,
new Ranch/Vendor navigation, milk collection sessions, composer and source detail.

## Continue on laptop

1. Preserve any local edits, fetch origin, then switch to the working branch.
   If the branch exists locally, update without discarding local commits/changes.
2. Read this file, CHANGE_REVIEW.md and the newest PR CI logs. The entire current
   implementation is in GitHub; no cloud scratch file is needed.
3. Fix the Firestore test failure. The independent test runner is:
   `node test/run_rules_checks.cjs`, under the emulator configured by
   `firebase.test.json`, project `demo-vimo`. The workflow shows exact setup.
4. Verify live Firebase permission/connectivity with the affected user. Check
   username availability/reservation, post creation, schedule visibility and
   private chat. Verify automatic sync between two signed-in devices, including
   offline edits followed by reconnect and another edit during upload.
5. Run required affected tests once fixes are complete; no need to repeat passed
   unrelated tests. Build using `flutter build web --release`.
6. Use the laptop's authorized Firebase login to deploy hosting, firestore rules
   and indexes to `my-ranch-sync`; wait for indexes to become ready. Keep the same
   production URL. Do not claim success until a fresh deployed client is checked.
7. Update the PR with final evidence and report clearly what is live.

## Relevant files

`lib/main.dart`: sync, settings, navigation, ranch reports/export.
`lib/vendor_stock_separation.dart`: vendor opening stock and historical cutover.
`lib/ranch_inventory.dart`: Ranch/Vendor workspaces and vendor reports.
`lib/business.dart`: vendor ledger, collection/bulk/sale screens.
`lib/account.dart`: username handling.
`lib/social.dart`: feed, composer/drafts, scheduling/deletion.
`lib/social_profile.dart`: profile design and public tabs.
`lib/community.dart`: search, requests, personal/business chat, milk origins.
`firestore.rules`, `firestore.indexes.json`: deploy together with the app.
