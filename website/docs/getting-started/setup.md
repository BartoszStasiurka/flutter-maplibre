---
title: 'Installation'
icon: lucide/sparkles
description: 'Add maplibre to a Flutter app and check the supported platforms and versions.'
---

# Installation

## Add the dependency

!!! info "Upgrading from 0.3.x"

    Version 0.4 changes much of the API. Read the
    [migration guide](../migrate/upgrade-from-v0.3.x.md) when you upgrade.

=== "Run command"

    Add `maplibre` to your project by running this command:

    ```bash
    flutter pub add maplibre:^0.4.0
    ```

=== "Edit `pubspec.yaml`"

    Alternatively, add it directly as a dependency to your `pubspec.yaml` file:

    ```yaml title="pubspec.yaml" hl_lines="2"
    dependencies:
      maplibre: ^0.4.0
    ```

    and then run `flutter pub get` to install the package.

    ```bash
    flutter pub get
    ```

The packages need Dart 3.13 and Flutter 3.47 or newer. Some platforms need
setup steps, see [Platform setup](platforms.md).

## Plugins

| Package               | Used for                                                                                                    |
|-----------------------|-------------------------------------------------------------------------------------------------------------|
| `maplibre_geolocator` | Shows the positions of [geolocator](https://pub.dev/packages/geolocator) as [user location](../user-location.md) |

## Platform support

| Platform | Implementation    | Renderer        | Rendering backend                      | Minimum version         |
|----------|-------------------|-----------------|----------------------------------------|-------------------------|
| Web      | `maplibre_web`    | MapLibre GL JS  | WebGL 2                                | Browsers with WebGL 2   |
| Android  | `maplibre_native` | MapLibre Native | OpenGL ES 3.0 (default) or Vulkan      | Android 7.0 (API 24)    |
| iOS      | `maplibre_native` | MapLibre Native | Metal                                  | iOS 15                  |
| macOS    | `maplibre_native` | MapLibre Native | Metal                                  | macOS 14.3              |
| Windows  | `maplibre_native` | MapLibre Native | Vulkan, shared with Flutter via D3D11  | Vulkan 1.1 driver       |
| Linux    | `maplibre_native` | MapLibre Native | Vulkan, shared with Flutter via OpenGL | Vulkan 1.1 driver       |

!!! warning "Only on web"

    Projections other than Mercator and `VideoSource` are only supported on
    web. On every other platform, `setProjection` keeps Mercator.

## Development version

!!! warning

    The development version is not considered stable and shouldn't be
    used in production systems.

Depend on the packages from the Git repository. `maplibre` depends on
the other packages by version, so override them, too:

```yaml title="pubspec.yaml"
dependencies:
  maplibre:
    git:
      url: https://github.com/maplibre/flutter-maplibre
      path: packages/maplibre

dependency_overrides:
  maplibre_native:
    git:
      url: https://github.com/maplibre/flutter-maplibre
      path: packages/maplibre_native
  maplibre_platform_interface:
    git:
      url: https://github.com/maplibre/flutter-maplibre
      path: packages/maplibre_platform_interface
  maplibre_web:
    git:
      url: https://github.com/maplibre/flutter-maplibre
      path: packages/maplibre_web
```
