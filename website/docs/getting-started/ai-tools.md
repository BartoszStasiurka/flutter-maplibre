---
title: 'AI tools'
description: 'Give AI coding assistants the current maplibre docs through llms.txt and llms-full.txt.'
icon: lucide/bot
---

# Using with AI tools

AI assistants often know only older versions of `maplibre` or confuse it with
`maplibre_gl`. Point them to the docs below; they follow the
[llms.txt](https://llmstxt.org) format and are rebuilt with the website.

## Docs for assistants

| File                                                                   | Content                                                    |
|------------------------------------------------------------------------|------------------------------------------------------------|
| [`llms.txt`](https://maplibre.org/flutter-maplibre/llms.txt)           | API summary and an index of all pages. Start here.         |
| [`llms-full.txt`](https://maplibre.org/flutter-maplibre/llms-full.txt) | All guides in one file. Large.                             |
| `<page>.md`                                                            | One page: replace the trailing `/` of its URL with `.md`, e.g. [`docs/map.md`](https://maplibre.org/flutter-maplibre/docs/map.md). |

## Setup

Add this to your assistant's rules file (`AGENTS.md`, `CLAUDE.md`,
`.cursor/rules` or `.github/copilot-instructions.md`):

```markdown
This app uses the Flutter package `maplibre` 0.4. Before writing map code,
read https://maplibre.org/flutter-maplibre/llms.txt. Its API differs from
older versions and from maplibre_gl.
```

For a docs index such as Cursor's `@Docs`, add
`https://maplibre.org/flutter-maplibre/llms-full.txt`.

## Migration skill

[`maplibre-migrate`](https://github.com/maplibre/flutter-maplibre/tree/main/skills/maplibre-migrate)
is an [Agent Skill](https://agentskills.io) that moves an app to `maplibre`
0.4 from 0.3, `maplibre_gl`, `flutter_map`, `google_maps_flutter` or
`mapbox_maps_flutter`.

1. Copy the `maplibre-migrate` folder into your assistant's skills folder,
   such as `.claude/skills/` for Claude Code.
2. Ask the assistant to migrate the app.

Assistants that fetch skills themselves can use
[`skills/maplibre-migrate/SKILL.md`](https://maplibre.org/flutter-maplibre/skills/maplibre-migrate/SKILL.md).

## Writing code for 0.4

- Code for 0.3 or older doesn't compile. Signs: `featuresAtPoint`,
  `MapOptions(initCenter: …)`, `setStyle`, styles as strings, and the
  `maplibre_android`, `maplibre_ios` and `maplibre_webview` packages. See the
  [migration guide](../migrate/upgrade-from-v0.3.x.md).
- Declarative: `MapLibreMap` parameters and annotation layers (`CircleLayer`,
  `MarkerLayer`, `PolylineLayer`, `PolygonLayer`, `WidgetLayer`); change
  them with `setState()`.
- Imperative: sources and style layers, through `style.sources` and
  `style.layers`, usually in `onStyleLoaded`.
- Variants are sealed classes with named constructors: `MapStyle.url`,
  `CameraUpdate.position`, `CameraAnimation.fly`, `QueryGeometry.point`,
  `GeoJsonData.featureCollection`, `MarkerIcon.asset`.
- Style layer properties and filters take `Expression<T>`; write constants as
  `const .literal(…)`.
- Positions are `Geographic(lon: …, lat: …)`, bounds are `GeoBox` (geobase,
  re-exported).
- Feature queries and camera methods return futures; `await` them.

## More

- [API reference](https://pub.dev/documentation/maplibre/latest/maplibre/):
  every class and parameter.
- [API guidelines](../contributing/api-guidelines.md): why the API looks the
  way it does, for extending it or writing plugins.
