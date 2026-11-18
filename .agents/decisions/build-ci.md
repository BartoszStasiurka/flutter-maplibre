# Build and CI

- **A local C build is named in the root `pubspec.yaml` as
  `hooks.user_defines.maplibre_native_ffi.local_build`, a maplibre-native-ffi
  CMake build root.** The hook takes `<preset>/install` under it for each
  target, so one setting serves every platform and Android ABI.
- **ffigen, jnigen and the style layer generator run from `tool/codegen`, a
  package outside the workspace.** The generators need newer native-asset
  packages than the binding allows. The style layer generator pins the npm version of the
  style spec and downloads its `v8.json`; the spec isn't committed. Outside the workspace, the binding's build hook doesn't run
  during code generation. jnigen uses the example app's Gradle classpath.
  The Kotlin API takes and returns only Android types (`Context`,
  `Surface`), which jnigen binds as stubs, so classes compiled against any
  `android.jar` give the same bindings.
- **`package:jni` is also an FFI plugin on Windows and Linux.** It builds
  there but stays unused.
- **CI builds and tests against the published C library.** No job builds it
  from source.
- **`llms.txt` and `llms-full.txt` are generated in the site build, not
  committed.** Zensical has no plugin for them, and generated files can't
  fall behind the pages.
- **CI has no build-only jobs for platforms the integration tests run on.**
  Each integration test job builds the example app for its platform. Only
  the web wasm build has its own job, as the tests run the JavaScript build.
