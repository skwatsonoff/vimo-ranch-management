# VIMO - Ranch, Vendor & Market

VIMO is an offline-first ranch management web app built with Flutter. It keeps
daily work available in the browser through Hive and syncs signed-in family
members through Firebase.

## Ranch, vendor and market workspaces

- New workspaces ask for their purpose. Existing users choose on their first
  visit after this update. Settings → Preferences changes purpose and the order
  of Ranch, Vendor, Sell, Social and Chat. Preferences are per account on this
  device. The first destination opens at launch; changing purpose preserves data.
- Cows and calves remain accessible inside Ranch. Sell contains Sell, Stock and
  Reports. Vendor purpose routes Sell and Stock to the vendor milk ledger.
- Vendor suppliers and customers have separate lists. Customers store address,
  delivery weekdays, morning/evening sessions and daily, every-two-days, weekly,
  monthly or flexible payment terms. Delivery reminders reflect scheduled sessions
  without marking them delivered until an actual sale is recorded.
- Purchases add vendor milk; deliveries deduct it. Paid amounts and later payments
  update each person's outstanding balance. Vendor stock is separate from ranch
  milk. The ledger and customer list appear in backups and the Excel workbook.
- Vendor financial entries require a connection. Firestore transactions update
  the ledger, milk balance and person's balance atomically, with retry IDs and
  server rules preventing negative stock, overpayments and arbitrary edits.
  The original author may update notes for five minutes, enforced by server time.
  Vendor data streams live to approved workspace members. Financial records are
  cloud-authoritative and are not re-uploaded by bulk backup sync.
- Social posts use the member's VIMO Ranch ID and are visible to signed-in VIMO
  users across workspaces. Posts support text, colored text tiles, one compressed
  photo and a voice clip up to 20 seconds. Members can like and comment. Authors
  can delete their own posts/comments. The feed shows the latest 60 posts, with
  up to 100 comments per post. Private ranch records are never part of the feed.
- Offline and sync explanations now live in Settings → Info. Existing ranch
  workflows continue to store their records locally.

## Validation

Run `flutter analyze lib test` and `flutter test`. The active source is in `lib`;
archived source ZIPs and directories are not part of the app.

`test/firestore_rules_test.cjs` tests vendor stock, payment balances, concurrent
sales, immutable financial fields, the five-minute edit window, cross-workspace
isolation and social ownership rules. It runs only against the demo emulator:

```powershell
npm install --prefix tmp/rules-qa --no-save @firebase/rules-unit-testing firebase
$env:NODE_PATH = (Resolve-Path 'tmp/rules-qa/node_modules').Path
npx --yes firebase-tools emulators:exec --config firebase.test.json --project demo-vimo --only firestore 'node test/firestore_rules_test.cjs'
```

The emulator requires Java 21 or newer. Preview builds use
`flutter build web --release --dart-define=VIMO_PREVIEW_MODE=true --output=tmp/business-preview`.
Never deploy that preview directory. Production uses `flutter build web --release`
and `firebase deploy --only hosting,firestore:rules --project my-ranch-sync`.

## Included

- Email sign-in, account creation, password reset, and remembered sessions
- Dashboard, cows, calves, animal profiles, milk, Vaikol/Thavudu stock,
  doctor, pregnancy, purchases, sales, deaths, calving, expenses, and reports
- Monthly top-three milk ranking and active-animal birthday reminders
- Offline local storage, backup/restore, individual CSV exports, one complete
  multi-sheet Excel workbook, and automatic cloud sync
- Responsive installable PWA with VIMO Liquid Glass styling
- Private ranch membership with Admin, Editor, Basic Entry, and Viewer roles
- Admin approval for join requests and a pending/cancel flow for applicants
- First-calving lifecycle that promotes a heifer to the cow list, starts her
  lactation, and links the newborn calf to its mother
- Safe browser photo uploads with orientation correction, resizing, and cloud
  size limits
- Stock ledger where purchases add kilograms and daily usage deducts kilograms;
  the purchase is counted as an expense once and usage is never double-counted
- Frequency-ranked suggestions for Other expense names and milk customers;
  selecting a returning milk customer restores their latest quantity

## Run locally

1. Install Flutter and enable web support.
2. On Windows, double-click `RUN_VIMO_WEB.bat`.

Alternatively, open a terminal in the folder containing `pubspec.yaml`, then
run `flutter pub get` followed by `flutter run -d chrome`.

## Make a production web build

Run `flutter build web --release`.

The deployable website is written to `build/web`.

Deploy every web update to the existing Firebase Hosting site. The permanent
production URL stays `https://my-ranch-sync.web.app`; a new deploy replaces the
app code without changing the URL or deleting Firestore ranch data.

## Android / Play Store updates

Before the first Play Store release, choose the final Android `applicationId`
and create one upload signing key. Never change that application ID or lose the
signing key. For every update, increase `version`/build number in
`pubspec.yaml`, build an Android App Bundle with `flutter build appbundle`, and
upload the new `.aab` to the same Play Console app. Android then installs it as
an update; Hive data remains on the device and Firebase data remains in the
ranch cloud account.

Back up the upload key securely and test each release in Play Console's
Internal testing track before Production.

## Firebase

The app is connected to the `my-ranch-sync` Firebase project. Enable Email /
Password authentication in Firebase Authentication before signing in. Firestore
rules in `firestore.rules` require an authenticated user for ranch data.

Each new ranch receives a unique Ranch ID. A second user can request to join an
existing ranch with that ID, but sees no ranch data until an Admin approves the
request. Admins can remove members and assign permissions from Family Users.

Firestore rules in `firestore.rules` enforce those roles on the server; the UI
is not the security boundary.

Stock and Other expense records are included in Firebase sync, JSON backup,
CSV expense export, and the complete Excel workbook. The Excel workbook uses
Courier New (typewriter style); CSV is plain text and cannot store a font.

The one-time `vimo_prelaunch_reset_20260826` migration intentionally clears
only pre-launch test data. Do not rename or repeat this marker in future
releases; keeping it unchanged ensures subsequent updates preserve user data.

## Animal lifecycle

- A female calf/heifer stays in **Calves** while pregnant.
- Recording **Calf Born** promotes the mother to **Cows**, preserves her old
  calf ID for history, assigns a cow ID, clears pregnancy, and starts lactation.
- The newborn is added to **Calves** with its mother link and birth details.
- The calving record is rolled back if any part of the operation fails, so the
  app does not leave half-saved animals.

## Visual preview

For local design testing without signing in:

`flutter run -d chrome --dart-define=VIMO_PREVIEW_MODE=true`

The normal production build never enables this preview unless the flag is
explicitly supplied.
