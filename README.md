# VIMO - My Ranch

VIMO is an offline-first ranch management web app built with Flutter. It keeps
daily work available in the browser through Hive and syncs signed-in family
members through Firebase.

## Included

- Email sign-in, account creation, password reset, and remembered sessions
- Dashboard, cows, calves, animal profiles, milk, feed, doctor, pregnancy,
  purchases, sales, deaths, calving, expenses, and reports
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

## Run locally

1. Install Flutter and enable web support.
2. On Windows, double-click `RUN_VIMO_WEB.bat`.

Alternatively, open a terminal in the folder containing `pubspec.yaml`, then
run `flutter pub get` followed by `flutter run -d chrome`.

## Make a production web build

Run `flutter build web --release`.

The deployable website is written to `build/web`.

## Firebase

The app is connected to the `my-ranch-sync` Firebase project. Enable Email /
Password authentication in Firebase Authentication before signing in. Firestore
rules in `firestore.rules` require an authenticated user for ranch data.

Each new ranch receives a unique Ranch ID. A second user can request to join an
existing ranch with that ID, but sees no ranch data until an Admin approves the
request. Admins can remove members and assign permissions from Family Users.

Firestore rules in `firestore.rules` enforce those roles on the server; the UI
is not the security boundary.

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
