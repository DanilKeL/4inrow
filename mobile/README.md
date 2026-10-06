# FOUR³ Flutter client

Native iOS/Android client. Flutter is pinned with FVM; web and backend remain in the repository as the behavior reference.

## Run

```sh
fvm install
fvm flutter pub get
fvm flutter run
```

The app uses `https://4inrow.ru` by default. To run against a local backend,
pass `--dart-define=FOUR_API_BASE_URL=http://127.0.0.1:3000`; for an Android
emulator use `http://10.0.2.2:3000`. Override `FOUR_ONLINE_URL` only when the
WebSocket endpoint is not derived from the API host.

## Architecture

Features follow the same layered shape throughout the app:

```text
Widget -> Scope/BLoC -> Repository -> Datasource -> RestClient
                                             \----> PreferencesDatasourceTool
```

- `domain/` contains feature models and repository contracts.
- `data/datasource/` owns transport or persistence details.
- `data/repository/` implements domain contracts by coordinating datasources.
- `bloc/` contains separate event, state, and BLoC files connected with normal
  imports; Dart `part` files are not used.
- `widget/` keeps small screen-specific widgets private and close to the screen.
  Only large or reusable UI is promoted to its own file under the feature or
  `feature/components/`.

`SharedPreferences` is an infrastructure detail. Feature code accesses it only
through `PreferencesDatasourceTool` and a feature-specific preferences
datasource. Preference keys, default values, and serialization belong to that
datasource—not to repositories, BLoCs, widgets, or services. The composition
root is the only place that creates the underlying `SharedPreferences` instance.

UI must be represented by `StatelessWidget` or `StatefulWidget` classes rather
than functions returning `Widget`. Theme access goes through the app theme
extensions (`context.colors` and `context.textStyle`) so shared visual tokens
remain centralized.

## Verification

```sh
fvm flutter analyze
fvm flutter test
fvm flutter test integration_test/game_scene_picking_test.dart -d <ios-device-id>
fvm flutter test integration_test/app_flow_test.dart -d <ios-device-id>
fvm flutter build apk --debug
fvm flutter build ios --simulator --debug
```

Build artifacts are written to `build/app/outputs/flutter-apk/app-debug.apk`
and `build/ios/iphonesimulator/Runner.app`. Android debug builds allow local
cleartext traffic for `10.0.2.2`; iOS allows local-network debug servers. Store
configuration remains HTTPS/WSS-only as described in
`../docs/mobile-store-release.md`.

The 3D acceptance run must use an iPhone 11 and a Snapdragon 730-class Android phone. In Flutter DevTools Performance view, warm up the scene, fill all 125 cells, orbit/zoom, raycast in every camera, toggle x-ray/layers, show a winning line, then enter/leave the scene 20 times. Acceptance: ≥55 FPS at `renderScale >= .75`, no black frames/GPU crashes, correct picks, and no sustained heap/GPU growth. Capture fixed empty/filled/x-ray/win frames and compare at SSIM ≥.95 against approved baselines.

`flutter_scene` is pinned to 0.23.0. Upgrade it only in a dedicated visual/performance regression task. If the gate fails, replace the scene adapter with Thermion; game, BLoC and UI layers must remain unchanged.
