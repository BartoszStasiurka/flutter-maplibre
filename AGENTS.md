# AGENTS.md

Flutter MapLibre: a federated plugin in a Dart pub workspace.

Start here. This file says where the code is, how to check a change and
where each rule is written down. Every rule and decision lives in exactly
one place: read it there, change it there, and link to it instead of
repeating it.

## Where the rules are

Read the file for the area you change before you change it.

| Area                                                                | File                                                                                                   |
|---------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------|
| Public API, dartdoc, docs wording, platform type conversions        | `website/docs/contributing/api-guidelines.md`                                                          |
| Packages, rendering through `Texture` only, plugin calls through ffigen and jnigen only, engines, threading, GPU | `.agents/decisions/architecture.md`                                           |
| The Windows, Linux, Android, or iOS and macOS plugin                | `.agents/decisions/windows.md`, `linux.md`, `android.md`, `apple.md`                                    |
| `MapLibreMap`, options, events, plugins, camera, queries, network   | `.agents/decisions/map-api.md`                                                                         |
| Sources, style layers, expressions, style images                    | `.agents/decisions/style-api.md`                                                                       |
| Annotation layers and their manager                                 | `.agents/decisions/annotations.md`                                                                     |
| Offline regions and the database                                    | `.agents/decisions/offline.md`                                                                         |
| User location                                                       | `.agents/decisions/user-location.md`                                                                   |
| Gestures (recognized once, in `MapGestureDetector`)                 | `.agents/decisions/gestures.md`                                                                        |
| Unit and integration tests                                          | `.agents/decisions/tests.md`                                                                           |
| Build, code generation, CI, the docs site                           | `.agents/decisions/build-ci.md`                                                                        |
| What `maplibre_native_ffi` lacks, and the workarounds               | `.agents/decisions/ffi-gaps.md`                                                                        |

`website/docs/contributing/architecture.md` explains how the packages fit
together, with diagrams.

## Layout

- `packages/maplibre`: the app-facing package.
- `packages/maplibre_platform_interface`: the shared API that the platform
  packages implement, and the shared gesture recognizer
  (`lib/src/gestures/`).
  - `lib/src/layer/`: the annotation layers of `MapLibreMap.layers`;
    `annotation_manager.dart` with its parts `annotation_images.dart` and
    `annotation_drag.dart`, and the pure `annotation_placement.dart`.
  - `lib/src/style/`: `style_owner.dart`, `expressions/`, `layers/` (with
    `style_layers.g.dart` and the light `style_light.g.dart`, generated from
    the style spec), `sources/` (with `FeatureRef` and the feature state of
    `style_sources.dart`), `style_state.dart` (global state, and the mixin of
    the light, global state and transition), and
    `style_backend.dart`, what the style collections need from a platform.
  - `lib/src/widget/`: `MapLibreMap` and its state, `map_plugin.dart`,
    `map_plugin_registry.dart`, and `inherited_model.dart` behind
    `MapController.of`, `CameraPosition.of` and `MapOptions.of`.
  - `lib/src/network.dart`: `MapLibreNetwork`.
- `packages/maplibre_web`: web, on maplibre-gl-js.
- `packages/maplibre_geolocator`: adapter from `geolocator` positions to
  `UserLocationLayer`.
- `packages/maplibre_native`: every other platform, on the C API of
  `maplibre_native_ffi` from pub.dev.
  - `lib/src/frame_target.dart`: `MapRenderer` and the `FrameTarget` of
    each platform (`lib/src/<platform>/*_target.dart`).
  - `lib/src/database.dart` and `lib/src/offline_manager.dart`.
  - `desktop/`: C++ shared by the Windows and Linux plugins; its C API
    `desktop/include/maplibre_native/maplibre_native_api.h` is bound in
    `lib/src/desktop/bindings.g.dart`.
  - `windows/`, `linux/`: the C++ plugins.
  - `android/`: the Kotlin plugin; `MaplibreNativeApi.kt` is bound in
    `lib/src/android/bindings.g.dart`.
  - `darwin/`: the Objective-C plugin for iOS and macOS, a SwiftPM package;
    its C API
    `darwin/maplibre_native/Sources/maplibre_native/include/maplibre_native/maplibre_native_api.h`
    is bound in `lib/src/darwin/bindings.g.dart`.
- `examples/`: the example app, which runs the integration tests on every
  platform. `integration_test/all_test.dart` runs them in one launch;
  `integration_test/shared/test_map.dart` has the `TestMap` helpers.
- `website/`, `mkdocs.yml`: the docs site, built by
  `.github/workflows/docs.yml`, which also deploys it with the web demo
  from main. Links from the site to the demo are relative (`demo/`,
  `../../demo/`), because the site lives under a subpath.
- `.github/scripts/llms_txt.py`: run after `zensical build`; writes
  `llms.txt`, `llms-full.txt`, a Markdown copy of every page and the skills
  of `skills/` into `site/`.
- `.github/scripts/watchdog.sh`: stops a stalled CI test run (see
  `tests.md`).
- `skills/`: agent skills for app developers (`maplibre-migrate`). They
  link to the docs pages instead of copying them.
- `tool/codegen/`: the ffigen, jnigen and style layer generators, a package
  outside the workspace (see `build-ci.md`).

## Commands

Run these from the repo root unless noted:

```bash
dart format $(git ls-files '*.dart')
dart analyze --fatal-warnings --fatal-infos
flutter test                                  # inside a package
cd examples && flutter test integration_test/all_test.dart -d windows  # or linux, macos, an iOS simulator, an Android device
cd examples && flutter drive --driver test_driver/integration_test.dart --target integration_test/all_test.dart -d web-server --browser-name chrome  # needs chromedriver on port 4444
cd tool/codegen && dart run ffigen.dart       # after changing the desktop or Darwin C API header
cd tool/codegen && dart run jnigen.dart       # after changing MaplibreNativeApi.kt; build examples for Android in release first
cd tool/codegen && dart run style_layers.dart # after raising the style spec version in the script
pip install zensical pyyaml && zensical build --clean && python3 .github/scripts/llms_txt.py  # docs site
packages/maplibre_native/linux/test/run_gl_texture_test.sh  # Linux zero-copy check, no Flutter build needed
```

Building the C library locally is covered in `CONTRIBUTING.md`.

## Working rules

- Record a decision once, in the file of its area: the decision in bold,
  then why. Change an existing entry instead of adding a second one, and
  link to another file instead of restating it. A missing feature of
  `maplibre_native_ffi` goes to `ffi-gaps.md`.
- Update this file, the guidelines and the decision files in the same commit
  as the change they describe.
- Never edit `*.g.dart` by hand. Change the generator in `tool/codegen/`.
- Use conventional commits (`feat(native): …`, `fix: …`, `ci: …`).
- Bugs, features and other open work are tracked in GitHub issues, not in
  files in the repository.
