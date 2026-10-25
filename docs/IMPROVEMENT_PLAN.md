# VIMO — premium polish plan (branch `ui-polish`)

Resume rule: work top to bottom; an unticked box is the next job. Every
finished step is a local commit on `ui-polish` (nothing is pushed or deployed).

## App map (Phase 0)

**Structure.** One Dart library: `lib/main.dart` (~20k lines) plus 25 `part`
files. State lives in Hive boxes (offline first) and syncs to Firestore
(`AutoSyncService`, `CloudSyncService`, `CollaborationRealtimeSyncService`).

**Navigation.** `VimoApp` → `AuthGate` → `RanchAccessGate` →
`MemberAwareShell` → `MainShell` (floating Liquid Glass tab bar `_NavBar`,
tabs chosen per role/purpose: Home, Animals, Vendor, Shop, Reports, Social,
Chat, Profile, Nearby, Settings). Pages push with `LiquidRoute` (iOS slide +
edge swipe back); sheets use `showAppleSheet`; alerts use `AppleAlert`.

**Screens.**
- Access: `LoginScreen`, `SignupScreen`, `UsernameScreen`,
  `RanchOnboardingScreen`, `WaitingApprovalScreen`, `PreferencesScreen`.
- Ranch: `DashboardScreen`, `AnimalsScreen`, `AnimalProfileScreen`,
  `AddAnimalScreen`, `AddEntryScreen` (milk/feed/expense…), `DoctorScreen`,
  `CalfBornScreen`, `PregnantCowsScreen`, `SellAnimalScreen`, `DeathScreen`,
  `SellScreen` (milk sales, balances), `RecordListScreen`,
  `MaleWorkEntryScreen`, `RanchChatScreen`, `TaskComposerScreen`,
  `NotificationHistoryScreen`.
- Reports: `ReportsScreen`, `ReportDetailScreen`, `ReportDetailsScreen`,
  `RecordFullDetailsScreen`, `ExportReportScreen`, `CustomerReportsScreen`,
  `CustomerMonthlyReportScreen`.
- Vendor: `VendorScreen`, `VendorStockScreen`, `VendorPersonScreen`,
  `VendorRideScreen`, `VendorProvidersScreen`, `VendorCustomizeScreen`,
  route maps (`RouteMapsScreen`, `RouteRecorderScreen`, `RouteViewScreen`,
  `RouteInviteScreen`, `RouteRideScreen`, `LocationPickerScreen`).
- Shop: `MilkShopScreen`, `ShopStockScreen`, `ShopSalesScreen`,
  `ShopCustomizeScreen`.
- Social / community / market: `SocialScreen`, `SocialProfileScreen`,
  `ProfilePeopleScreen`, `EditSocialProfileScreen`, `CommunitySearchScreen`,
  `CommunityChatsScreen`, `DirectChatScreen`, `MilkOriginScreen`,
  `NearbyScreen`, `MarketVendorScreen`, `MarketListingScreen`,
  `SharedAnimalScreen`, `SharedPostScreen`.
- Settings: `SettingsScreen`, `RanchSettingsScreen`, `AppSettingsScreen`,
  `FamilyUsersScreen`, `FirebaseSyncScreen`, `WorksOfflineScreen`,
  `AppInfoScreen`.

**Theme / shared widgets.** `Gold` (phi spacing, radii, type, durations),
`Ink` (semantic light/dark colours + brand tint), `appleTheme()`,
`squirclePath`/`SquircleBorder`, `Glass` (solid grouped cell), `LiquidGlass`
(functional-layer glass), `Pressable`, `Shell`, `LiquidRoute`,
`LiquidButton`, `GhostButton`, `Segment`, `LiquidSegmentBar`, `fieldStyle`,
`snack`, `showAppleSheet`, `AppleAlert`, `SectionTitle`, `InfoRow`,
`DataCard`, `SyncChip`, `EmptyNote`, `SuggestionField`, `DateField`,
`PickerField`, `GlassAvatar`, `RanchIcon`, `CowMark`, rank painters
(`RankTexturePainter`, `RankAuraPainter`, `Rosette`). `DevicePerformance`
(lib/performance.dart) decides low-end fallbacks.

**Packages (relevant).** hive/hive_flutter (offline store), firebase_*
(auth, firestore, messaging), flutter_animate, audioplayers (already used for
voice notes), google_fonts + bundled Inter/Parisienne, flutter_map,
geolocator, record, file_picker, url_launcher.

## Checklist

### Phase 0 — Baseline
- [x] Flutter installed inside project (`tmp/flutter`), versions recorded
- [x] Baseline analyze / test counts in `docs/QA_REPORT.md`
- [x] App map (above)

### Phase 1 — Audit
- [x] Skills loaded: apple-look, apple-motion, design-taste-frontend,
      awesome-design-md (apple), web-design-guidelines (Phase 6)
- [ ] Screens captured (preview build) and reviewed
- [ ] `docs/UI_AUDIT.md` written (What / Why / Fix, most important first)

### Phase 2 — Design system and UI
- [ ] Tokens: VIMO Milk palette, spacing 4/8 scale, radii, shadows, blur
      levels, durations, springs (one theme layer)
- [ ] Lavender canvas + brand purple tint, orange accent, cream warm surface
- [ ] Glass fallbacks (reduce transparency / high contrast / low-end)
- [ ] Type hierarchy (600 headlines, tracking by size)
- [ ] Screen fixes from audit (commit per screen)

### Phase 3 — Motion
- [ ] Spring tokens + reduce-motion helper
- [ ] Animated milk totals (count-up)
- [ ] Skeleton shimmer for loading states
- [ ] List enter / exit, card press, success / error feedback
- [ ] Pull to refresh where data syncs
- [ ] RepaintBoundary / const audit on heavy lists

### Phase 4 — Workflows
- [ ] Milk entry, sell milk, expense, cow/calf, vet, pregnancy reviewed
- [ ] Customer → last quantity auto-fill; expense names by frequency
- [ ] Undo instead of confirm where safe; clear success states

### Phase 5 — Sound
- [ ] Sound set rendered (tap, toggle on/off, success, error, whoosh,
      notification) into `assets/sounds/`
- [ ] `UiSound` service, preloaded, low-latency
- [ ] Settings → Sounds switch (default on), respects silent mode

### Phase 6 — Testing
- [ ] analyze clean for touched code; widget tests for changed screens
- [ ] `flutter test` green
- [ ] web build + Playwright click-through (phone + desktop), console errors
- [ ] web-design-guidelines review
- [ ] offline / empty / long-text / Tamil checks
- [ ] QA report final; final summary
