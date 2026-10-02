# FOUR³ Flutter client

Native iOS/Android client. Flutter is pinned with FVM; web and backend remain in the repository as the behavior reference.

## Run

```sh
fvm install
fvm flutter pub get
fvm flutter run --dart-define=FOUR_API_BASE_URL=http://127.0.0.1:3000
```

For an Android emulator use `http://10.0.2.2:3000`. Override `FOUR_ONLINE_URL` only when the WebSocket endpoint is not derived from the API host.

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
