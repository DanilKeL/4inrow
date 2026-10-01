# Browser verification

Mobile layout checks cover 320×568, 375×667, 390×844, 430×932, 667×375 and 844×390: menu, all setup modes, settings, tutorial, online lobby, long names, victory and replay. They assert document height/width, dialog content height, control bounds and lobby content bounds, so hiding overflow cannot make an off-screen button pass. Mobile game layouts use the available viewport height; only dialogs keep scrolling as a fallback for a keyboard or enlarged text.

`npm run test:e2e` runs desktop and 390 × 844 touch tests on Chromium. When its Playwright browser is unavailable on Windows, the configuration uses installed Microsoft Edge automatically. Installed Playwright Firefox and WebKit browsers are included automatically.

To require the complete three-engine matrix, install the browsers with `npx playwright install chromium firefox webkit`, then set `FULL_BROWSER_MATRIX=1` before running the tests. In PowerShell:

```powershell
$env:FULL_BROWSER_MATRIX = '1'
npm run test:e2e
```

`PLAYWRIGHT_CHANNEL` can explicitly select a Chromium channel, such as `msedge` or `chrome`. A run on Edge does not establish Firefox, Safari, or real-device compatibility. The mobile project emulates touch and viewport dimensions; it is not a physical phone test.

Tests click and tap projected coordinates on the actual Three.js canvas. The read-only development projection hook never changes game state. Assertions cover horizontal and spatial diagonal victories, replay, rematch, the five-piece cap, undo, orbit dragging, a hard AI reply, persisted settings, and pause/resume. X-ray and layer controls are checked against decoded canvas screenshot pixels with a measured idle-frame noise allowance. All 25 projected columns must fit inside both default and top cameras at 1920 × 1080, 1440 × 900, 1366 × 768, 390 × 844, 393 × 852, 430 × 932, and 844 × 390; the phone checks include a five-piece tower. Browser console warnings, errors, and uncaught exceptions fail the tests, with no browser warning exclusions.

Screenshots `desktop-menu.png`, `desktop-game.png`, and `mobile-game.png` are stored in the relevant test subdirectories under `test-results`. Failures retain a screenshot and Playwright trace. Open the HTML report with `npx playwright show-report`.

Online tests open independent browser contexts, create/join a five-letter lobby, play a complete synchronized match using real canvas clicks, request a mutual rematch, restore a refreshed tab, reject a third player, and close the peer lobby on explicit leave. `npm run dev` starts both the Vite frontend and lobby server; both must be running when reusing an existing development session.
