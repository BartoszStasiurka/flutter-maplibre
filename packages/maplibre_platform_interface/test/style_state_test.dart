import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_platform_interface/maplibre_platform_interface.dart';

import 'shared/recording_style_backend.dart';

void main() {
  late RecordingStyleBackend backend;

  setUp(() => backend = RecordingStyleBackend());

  group('feature state', () {
    late StyleSources sources;

    setUp(() async {
      sources = StyleSources(backend, layers: () => const []);
      await sources.add(const GeoJsonSource.url(id: 'g', url: 'https://g'));
      await sources.add(const VectorSource.url(id: 'v', url: 'https://v'));
      await sources.add(const RasterSource.url(id: 'r', url: 'https://r'));
      backend.calls.clear();
    });

    test('merges keys and reads them back', () {
      const feature = FeatureRef(sourceId: 'g', id: 1);
      expect(sources.featureState(feature), isEmpty);
      sources
        ..setFeatureState(feature, {'hover': true, 'rank': 2})
        ..setFeatureState(feature, {'hover': false});
      expect(sources.featureState(feature), {'hover': false, 'rank': 2});
      expect(
        sources.featureState(const FeatureRef(sourceId: 'g', id: 2)),
        isEmpty,
      );
      expect(backend.calls, [
        'setFeatureState FeatureRef(g, 1) {hover: true, rank: 2}',
        'setFeatureState FeatureRef(g, 1) {hover: false}',
      ]);
    });

    test('keeps source layers apart', () {
      const a = FeatureRef(sourceId: 'v', sourceLayer: 'a', id: 'x');
      const b = FeatureRef(sourceId: 'v', sourceLayer: 'b', id: 'x');
      sources.setFeatureState(a, {'on': true});
      expect(sources.featureState(a), {'on': true});
      expect(sources.featureState(b), isEmpty);
      sources.clearFeatureState('v', sourceLayer: 'a');
      expect(sources.featureState(a), isEmpty);
      expect(backend.calls.last, 'removeFeatureState v a null null');
    });

    test('removes one key, one feature or every feature', () {
      const one = FeatureRef(sourceId: 'g', id: 1);
      const two = FeatureRef(sourceId: 'g', id: 2);
      sources
        ..setFeatureState(one, {'hover': true, 'selected': true})
        ..setFeatureState(two, {'hover': true})
        ..removeFeatureState(one, key: 'hover');
      expect(sources.featureState(one), {'selected': true});
      sources.removeFeatureState(one);
      expect(sources.featureState(one), isEmpty);
      expect(sources.featureState(two), {'hover': true});
      sources.clearFeatureState('g');
      expect(sources.featureState(two), isEmpty);
      expect(backend.calls.skip(2), [
        'removeFeatureState g null 1 hover',
        'removeFeatureState g null 1 null',
        'removeFeatureState g null null null',
      ]);
    });

    test('goes with its source', () async {
      const feature = FeatureRef(sourceId: 'g', id: 1);
      sources.setFeatureState(feature, {'hover': true});
      await sources.remove('g');
      await sources.add(const GeoJsonSource.url(id: 'g', url: 'https://g'));
      expect(sources.featureState(feature), isEmpty);
    });

    test('drops the entry of a feature without state', () {
      const feature = FeatureRef(sourceId: 'g', id: 1);
      sources
        ..setFeatureState(feature, {'hover': true})
        ..removeFeatureState(feature, key: 'hover');
      expect(sources.featureState(feature), same(const <String, Object?>{}));
    });

    test('goes with updateTiles and updateTileJsonUrl', () async {
      await sources.add(
        const VectorSource.tiles(id: 't', tiles: ['https://t']),
      );
      const tiles = FeatureRef(sourceId: 't', sourceLayer: 'a', id: 1);
      const url = FeatureRef(sourceId: 'v', sourceLayer: 'b', id: 1);
      sources
        ..setFeatureState(tiles, {'on': true})
        ..setFeatureState(url, {'on': true});
      backend.calls.clear();
      await sources.updateTiles('t', ['https://u']);
      await sources.updateTileJsonUrl('v', 'https://w');
      expect(sources.featureState(tiles), isEmpty);
      expect(sources.featureState(url), isEmpty);
      expect(backend.calls.where((call) => call.startsWith('remove')), [
        'removeFeatureState t a null null',
        'removeFeatureState v b null null',
      ]);
    });

    test('does nothing for a missing source', () {
      const feature = FeatureRef(sourceId: 'missing', id: 1);
      sources
        ..setFeatureState(feature, {'a': 1})
        ..removeFeatureState(feature)
        ..clearFeatureState('missing');
      expect(sources.featureState(feature), isEmpty);
      expect(backend.calls, isEmpty);
    });

    test('checks the source type and its source layer', () {
      for (final feature in const [
        FeatureRef(sourceId: 'v', id: 1),
        FeatureRef(sourceId: 'g', sourceLayer: 'a', id: 1),
        FeatureRef(sourceId: 'r', id: 1),
      ]) {
        expect(
          () => sources.setFeatureState(feature, {'a': 1}),
          throwsArgumentError,
          reason: '$feature',
        );
        expect(() => sources.featureState(feature), throwsArgumentError);
      }
      expect(() => sources.clearFeatureState('v'), throwsArgumentError);
      expect(backend.calls, isEmpty);
    });

    test('a replaced style takes no change', () {
      const feature = FeatureRef(sourceId: 'g', id: 1);
      sources
        ..markReplaced()
        ..setFeatureState(feature, {'hover': true});
      expect(sources.featureState(feature), isEmpty);
      expect(backend.calls, isEmpty);
    });

    test('can clear the map when the style is replaced', () {
      sources
        ..setFeatureState(const FeatureRef(sourceId: 'g', id: 1), {'a': 1})
        ..setFeatureState(
          const FeatureRef(sourceId: 'v', sourceLayer: 'b', id: 1),
          {'a': 1},
        );
      backend.calls.clear();
      sources
        ..markReplaced(clearFeatureState: true)
        ..markReplaced(clearFeatureState: true);
      expect(backend.calls, [
        'removeFeatureState g null null null',
        'removeFeatureState v b null null',
      ]);
    });

    test('refers to a rendered feature', () {
      expect(
        FeatureRef.of(
          const RenderedFeature(
            id: 7,
            properties: {},
            sourceId: 'v',
            sourceLayer: 'roads',
          ),
        ),
        const FeatureRef(sourceId: 'v', sourceLayer: 'roads', id: 7),
      );
      expect(
        FeatureRef.of(
          const RenderedFeature(
            id: 7,
            properties: {},
            sourceId: 'g',
            sourceLayer: '',
          ),
        ),
        const FeatureRef(sourceId: 'g', id: 7),
      );
      expect(
        () => FeatureRef.of(
          const RenderedFeature(id: null, properties: {}, sourceId: 'g'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('global state', () {
    late _Style style;
    late StyleGlobalState state;
    const styleJson = {
      'state': {
        'units': {'default': 'metric'},
        'theme': {'default': 'day'},
      },
    };

    setUp(() {
      style = _Style(backend)..loadStyleState(styleJson);
      state = style.globalState;
    });

    test('reads the defaults, overridden by the values', () {
      expect(state, {'units': 'metric', 'theme': 'day'});
      style.applyGlobalState({'units': 'imperial', 'extra': 1});
      expect(state, {'units': 'imperial', 'theme': 'day', 'extra': 1});
      expect(() => state['units'] = 'x', throwsUnsupportedError);
    });

    test('sends only what changed, and defaults for removed values', () {
      style
        ..applyGlobalState({'units': 'imperial', 'theme': 'night'})
        ..applyGlobalState({
          'units': 'imperial',
          'theme': null,
          'list': [1, 2],
        })
        ..applyGlobalState({
          'units': 'imperial',
          'list': [1, 2],
        })
        ..applyGlobalState(const {});
      expect(backend.calls, [
        'setGlobalStateProperty units imperial',
        'setGlobalStateProperty theme night',
        'setGlobalStateProperty theme day',
        'setGlobalStateProperty list [1, 2]',
        'setGlobalStateProperty units metric',
        'setGlobalStateProperty list null',
      ]);
      expect(state, {'units': 'metric', 'theme': 'day'});
    });

    test('resets what the previous style set, once the defaults are known', () {
      style.applyGlobalState({'units': 'imperial', 'theme': 'night'});
      backend.calls.clear();
      // As not on web: the values go to the map before the style JSON is
      // read.
      final next = _Style(backend)
        ..applyGlobalState({'theme': 'night'}, previous: style);
      expect(backend.calls, ['setGlobalStateProperty theme night']);
      next.loadStyleState({
        'state': {
          'units': {'default': 'feet'},
        },
      });
      expect(backend.calls.last, 'setGlobalStateProperty units feet');
      expect(next.globalState, {'units': 'feet', 'theme': 'night'});

      // As on web: the style JSON first.
      backend.calls.clear();
      _Style(backend)
        ..loadStyleState(styleJson)
        ..applyGlobalState(const {}, previous: next);
      expect(backend.calls, ['setGlobalStateProperty theme day']);
    });

    test('a replaced style takes no change', () {
      style
        ..markStyleStateReplaced()
        ..applyGlobalState({'units': 'imperial'});
      expect(backend.calls, isEmpty);
      expect(state['units'], 'metric');
    });
  });

  test('transition', () {
    final style = _Style(backend)
      ..loadStyleState({
        'transition': {'duration': 100},
      });
    expect(style.transition.duration, const Duration(milliseconds: 100));
    style.transition = const StyleTransition(duration: Duration.zero);
    style
      ..markStyleStateReplaced()
      ..transition = const StyleTransition();
    expect(backend.calls, ['setTransition 0 0']);
  });

  group('light', () {
    test('reads the style light and sends the whole light', () {
      final light = StyleLight(backend)
        ..load({'anchor': 'map', 'intensity': 0.2});
      expect(light.anchor, const Literal(LightAnchor.map));
      expect(light.intensity, const Literal(0.2));
      expect(light.color, const Literal(Color(0xFFFFFFFF)));
      expect(light.position, const Literal(<num>[1.15, 210, 30]));
      light
        ..color = const .literal(Color(0xFFFF0000))
        ..intensityTransition = const StyleTransition(
          duration: Duration(seconds: 1),
        )
        ..anchor = null;
      expect(light.anchor, const Literal(LightAnchor.viewport));
      expect(light.intensityTransition?.duration, const Duration(seconds: 1));
      // The removed anchor goes to its default explicitly, as gl-js keeps
      // what is left out.
      expect(
        backend.calls.last,
        'setLight {anchor: viewport, intensity: 0.2, color: #ff0000, '
        'intensity-transition: {duration: 1000, delay: 0}}',
      );
      expect(backend.calls, hasLength(3));
    });

    test('resets a removed property and transition', () {
      final light = StyleLight(backend)..load(null);
      light
        ..intensity = const .literal(0.8)
        ..colorTransition = const StyleTransition()
        ..intensity = null
        ..colorTransition = null;
      expect(light.intensity, const Literal(0.5));
      expect(light.toJson(), isEmpty);
      expect(
        backend.calls.last,
        'setLight {intensity: 0.5, color-transition: {}}',
      );
    });

    test('a replaced style takes no change', () {
      final light = StyleLight(backend)
        ..load(null)
        ..markReplaced()
        ..intensity = const .literal(1);
      expect(light.intensity, const Literal(1));
      expect(backend.calls, isEmpty);
    });
  });

  test('MapOptions compare global state deeply', () {
    // Built at run time, so that they are not identical.
    MapOptions options() => MapOptions(globalState: {'a': List.filled(1, 1)});
    expect(options(), options());
    expect(options().hashCode, options().hashCode);
    expect(
      const MapOptions(globalState: {'a': 1}),
      isNot(const MapOptions(globalState: {'a': 2})),
    );
  });
}

/// A style controller with the shared style state, which sends its changes
/// to [backend].
class _Style extends StyleController with StyleStateMixin {
  _Style(this.backend);

  final RecordingStyleBackend backend;

  @override
  void setGlobalStateProperty(String name, Object? value) =>
      backend.setGlobalStateProperty(name, value);

  @override
  void setLight(Map<String, Object?> json) => backend.setLight(json);

  @override
  void setTransition(StyleTransition transition) =>
      backend.setTransition(transition);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
