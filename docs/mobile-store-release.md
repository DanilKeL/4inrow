# FOUR³ mobile — store release checklist

The Flutter client lives in `mobile/` and is pinned by FVM to Flutter 3.47.5. Debug builds use the `four3://` URL scheme. Store builds must not be submitted until every item below is completed.

## Accounts and identifiers

- Create or renew the Apple Developer Program and Google Play Console accounts owned by the product organization.
- Choose permanent identifiers. Replace the debug placeholder `com.example.four3` in the Xcode project and `android/app/build.gradle.kts` with the approved bundle/application IDs.
- Register the iOS App ID and the Android app in Play Console; reserve the public app name and SKU.
- Create an App Store Connect app and Play Console app using the same production identity.

## Signing

- Create the Apple Distribution certificate and App Store provisioning profile; enable automatic signing only for the owning team.
- Create a Play App Signing upload key, store it outside the repository, and configure `key.properties` through CI secrets.
- Record the production and debug SHA-256 signing fingerprints. Never commit certificates, passwords, keystores, or API keys.
- Produce signed archive/AAB builds in CI and verify their identifiers and entitlements before upload.

## Universal Links and App Links

- Select the production HTTPS domain used by API and email links.
- iOS: add the Associated Domains capability with `applinks:<domain>` and serve `https://<domain>/.well-known/apple-app-site-association` for the final Team ID and bundle ID.
- Android: add an `https` VIEW intent filter with `android:autoVerify="true"`, the final host and `/auth/verify` path; serve `https://<domain>/.well-known/assetlinks.json` containing the final application ID and every production SHA-256 certificate fingerprint.
- Keep `four3://verify?token=…` available in debug only. Production email uses `https://<domain>/auth/verify?token=…`; the web GET redirect remains the fallback when the app is absent.
- Verify cold start, warm start, expired token, reused token and app-not-installed behavior on physical iOS and Android devices.

## Backend and configuration

- Build with `--dart-define=FOUR_API_BASE_URL=https://<domain>` and, only if different, `--dart-define=FOUR_ONLINE_URL=wss://<domain>/online`.
- Confirm TLS, WebSocket upgrade, cookie flags, rate limits and the JSON `POST /auth/verify` response in production.
- Confirm `four_session` survives relaunch in secure storage and is accepted by both HTTP and WebSocket endpoints.
- Back up the account/statistics data and document rollback before deploying the mobile-compatible backend.

## Privacy and store metadata

- Complete Apple privacy nutrition labels and Google Play Data safety using actual collection: account identity/email, gameplay/history/rating and operational telemetry if enabled.
- Publish privacy policy, terms, account deletion instructions and support contact on public HTTPS pages.
- Complete encryption/export-compliance answers and age/content rating questionnaires.
- Prepare localized name, subtitle/short description, full description, keywords, category, support/marketing URLs and release notes.
- Prepare compliant phone screenshots for portrait and landscape, app icon, Play feature graphic and review notes/test account.

## Release acceptance

- Run `fvm flutter analyze`, `fvm flutter test`, server `npm test`, Android release build and iOS Release archive without warnings/errors.
- Execute the 3D performance matrix in `mobile/README.md` on an iPhone 11 and a Snapdragon 730-class Android device: warmed-up FPS ≥55 at render scale ≥0.75, no black frames/GPU crashes and no heap/GPU growth after 20 scene entries.
- Test account registration, email verification, login/logout, local/AI/all 40 levels, history replay, leaderboard, private lobby, ranked matchmaking, reconnect/resume, pause, rematch and background/foreground with two physical devices.
- Validate VoiceOver/TalkBack labels, Dynamic Type at supported sizes, reduced-animation setting, both phone orientations and loss/restore of network.
- Distribute first through TestFlight internal testing and Play internal testing. Promote only after crash-free and performance review.
