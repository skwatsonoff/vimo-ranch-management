VIMO sync and community changes — review status

Released 2026-09-16: PR #2 merged (`ace79b3`), with the final browser sync
transport correction in `2e65d34`. Hosting, Firestore rules and indexes are live
at https://my-ranch-sync.web.app. Fresh signed-in production verification showed
Synced, zero pending records and a current last-sync timestamp; profile feed and
username availability loaded without the previously reproduced SDK assertion.
See CODEX_HANDOFF.md's release section for evidence. Older blockers below are
historical and superseded by this release.

2026-09-15 laptop update: the prior emulator blocker is resolved. All 89 original
security checks plus seven authenticated HTTP feed checks pass. All 57 Flutter
tests pass. Browser integration reproduced and fixed the shared Firestore
watch-stream crash; status updates no longer rebuild the entire main shell.
Scheduled feeds use fresh authenticated HTTP queries, retaining time-based
privacy rules. Cross-account automatic upload, offline upload after reconnect,
username creation and post publication/feed rendering were verified locally.
The profile header is more compact and its Ranch tab has a clear cow silhouette.
See the newest section in CODEX_HANDOFF.md for exact evidence and release status.

HISTORICAL CHECKPOINT: Read CODEX_HANDOFF.md. GitHub emulator CI now runs but
found a social_posts GET permission failure; fix it before release. The latest
full Flutter suite passed 57 tests.
==============================================

Based on `codex/ranch-vendor-market-glass` at
`402a6f450b835fc94a14ef04adee4f86dbb6c7fb`, the branch containing the
screens in the request. The older main and Sites copies are not the base.

Implemented for review:

- Profile photo in the home header; profile settings at top right; vertically
  stacked posts; Post / Ranch / Vendor tabs. Followers precede Following.
- Optional public cow cards expose only name, ID, breed and photo. Ranch
  financial records are not published. Shop details have a separate opt-in.
- Automatic sync uses a bounded first-upload delay, preserves newer local
  edits, queues changed settings, and listens for remote ranch changes.
  Idle timers retry pending work rather than downloading every collection.
  Duplicate Sync Now / Upload buttons and the disable switch are removed.
- Username errors distinguish permissions, expired sessions and timeouts.
  Checks run on prefilled fields, normalize input, ignore stale responses, and
  reserve usernames in a transaction. Posting refreshes the server username.
- Stock and ledger entries open milk origin details, including source cow or
  supplier, recorded dates, amounts and purchase prices. Historical source
  details fall back to the linked local record when available.
- Personal chat includes the ranch group, active members and added contacts.
  Other social conversations appear in Business chat. Private messages use a
  separate durable, account-scoped outbox, outside ranch backup collections.
- Authors can delete or schedule posts. Future timestamps control visibility
  in Firestore rules; other users cannot retrieve a scheduled post early.
  Feeds refresh their time boundary every 30 seconds. This needs no scheduled
  function. The included Firestore index is required for profile queries.
- Prefix search for usernames and display names, and ranch name/ID search.
  Join requests do not clear the current ranch or its unsynced records.

Ranch / Vendor separation:

- Ranch has Overview, Cows, Calves, Sell, Stock and Reports. Sell includes milk,
  cows, calves and manure. Ranch report totals and report exports omit Vendor.
- Vendor has Collect milk, Buy milk, Sell milk, Milk stock and Reports.
  Collection records distinguish Morning / Evening. Collected and bulk-purchased
  quantities and costs appear separately, with a dedicated CSV report.
- New vendor ledger entries use stockScope vendor_v2 and vendor_stock/vendor_milk.
  No new ranch milk records credit vendor stock and no new vendor sales reduce
  ranch stock. Original ledger entries are retained. An admin initializes the
  separate vendor opening stock from the historical vendor-only net quantity;
  historical implicit ranch consumption remains accounted for in ranch totals.
- Deploy the rules and app together and update all clients: old versions using
  the shared stock document cannot create more mixed-ledger entries afterward.

Verification completed (2026-09-14):

- Flutter dependencies restored using CI=true, which prevents Flutter's metadata
  environment probe. No dependency versions were changed.
- All 56 existing/updated Flutter tests passed. The additional Ranch Sell widget
  check also passed in the business suite.
- Six dependency-free sync-core checks passed.
- Flutter analysis has no errors or warnings (only informational test lints).
- Production web build passed. Dart formatting and git diff checks passed.
- Composer draft initialization crash found by the tests was fixed.

Remaining release gates:

1. Run the three Firestore emulator suites, including stock concurrency, username,
   scheduled post visibility and private chat access. They could not execute here:
   the downloaded Java 21 runtime failed at startup with ClassFormatError in
   sun/misc/Unsafe. No production database was used for these tests.
2. Browser preview could not open the local server: ERR_BLOCKED_BY_CLIENT.
   Visual verification and the affected account's live Firebase flows remain open.
3. Verify two signed-in devices: new/edit/offline/reconnect sync, username
   contention, post/schedule/delete, private chat and ranch join requests.
4. Deploy hosting, Firestore rules and indexes together to my-ranch-sync and wait
   for the profile post index to become ready. Firebase CLI has no authorized
   account in this environment. No production deployment was performed.

Source publication is authorized by the user. This remains a draft until the
backend and live-device release gates pass. Do not claim the reported production
connection failures are resolved merely from local tests or a successful build.
