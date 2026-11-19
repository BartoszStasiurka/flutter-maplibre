import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre/maplibre.dart';
import 'package:material_ui/material_ui.dart';

import 'shared/test_map.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runTests();
}

const _point = Geographic(lon: 0, lat: 0);

/// A style with a point that only shows while the global state `show` is
/// true, and a light.
String _stateStyle({String background = 'background'}) => jsonEncode({
  'version': 8,
  'state': {
    'show': {'default': false},
    'radius': {'default': 40},
  },
  'light': {'anchor': 'map', 'intensity': 0.3},
  'transition': {'duration': 500, 'delay': 10},
  'sources': {
    'points': {
      'type': 'geojson',
      'data': featureCollection([const Feature(geometry: Point(_point), id: 1)])
          .toJson(),
    },
  },
  'layers': [
    {'id': background, 'type': 'background'},
    {
      'id': 'points',
      'type': 'circle',
      'source': 'points',
      'filter': [
        '==',
        ['global-state', 'show'],
        true,
      ],
      'paint': {
        'circle-radius': ['global-state', 'radius'],
      },
    },
  ],
});

MapOptions _options({
  Map<String, Object?> globalState = const {},
  String background = 'background',
}) => MapOptions(
  style: MapStyle.json(_stateStyle(background: background)),
  initCamera: const CameraUpdate.position(center: _point, zoom: 8),
  globalState: globalState,
);

void runTests() {
  group('style state', () {
    testWidgets('feature state changes what layers draw', (tester) async {
      final map = await pumpMap(tester, options: offlineOptions(zoom: 8));
      await map.style.sources.add(
        GeoJsonSource.data(
          id: 'src',
          data: featureCollection([
            const Feature(geometry: Point(_point), id: 1),
          ]),
        ),
      );
      const feature = FeatureRef(sourceId: 'src', id: 1);
      // Starts large, as gl-js searches only as far as the largest radius
      // when the tile loaded.
      map.style.sources.setFeatureState(feature, {'big': true});
      await map.style.layers.add(
        CircleStyleLayer(
          id: 'circles',
          sourceId: 'src',
          radius: .select([
            (
              Expression.equal(.featureState('big'), const .literal(true)),
              const .literal(40),
            ),
          ], fallback: const .literal(10)),
        ),
      );
      final beside = map.center + const Offset(25, 0);
      await map.waitForFeatures(beside, (features) => features.isNotEmpty);
      expect(map.style.sources.featureState(feature), {'big': true});

      map.style.sources.removeFeatureState(feature, key: 'big');
      await map.waitForFeatures(beside, (features) => features.isEmpty);
      expect(map.style.sources.featureState(feature), isEmpty);

      // From a query result.
      final rendered = await map.waitForFeatures(
        map.center,
        (features) => features.isNotEmpty,
      );
      map.style.sources.setFeatureState(.of(rendered.first), {'big': true});
      await map.waitForFeatures(beside, (features) => features.isNotEmpty);

      // It stays when the data changes.
      await map.style.sources.updateGeoJsonData(
        'src',
        featureCollection([
          const Feature(geometry: Point(_point), id: 1, properties: {'a': 1}),
        ]),
      );
      await map.waitForFeatures(
        beside,
        (features) => features.any((f) => f.properties['a'] == 1),
      );
      expect(map.style.sources.featureState(feature), {'big': true});

      map.style.sources.clearFeatureState('src');
      await map.waitForFeatures(beside, (features) => features.isEmpty);
    });

    testWidgets('applies MapOptions.globalState over the style defaults', (
      tester,
    ) async {
      final map = await pumpMap(tester, options: _options());
      expect(map.style.globalState, {'show': false, 'radius': 40});
      Future<void> expectShown({required bool shown}) => map.waitForFeatures(
        map.center,
        (features) => features.isNotEmpty == shown,
        layerIds: ['points'],
      );
      await expectShown(shown: false);

      await map.setOptions(_options(globalState: {'show': true}));
      await expectShown(shown: true);
      expect(map.style.globalState, {'show': true, 'radius': 40});

      final beside = map.center + const Offset(25, 0);
      await map.waitForFeatures(beside, (features) => features.isNotEmpty);
      await map.setOptions(_options(globalState: {'show': true, 'radius': 10}));
      await map.waitForFeatures(beside, (features) => features.isEmpty);

      // A removed value goes back to the default.
      await map.setOptions(_options(globalState: {'radius': 10}));
      await expectShown(shown: false);
      expect(map.style.globalState, {'show': false, 'radius': 10});

      // The values outlive a style switch.
      final oldStyle = map.style;
      await map.setOptions(
        _options(globalState: {'show': true}, background: 'other'),
      );
      await map.pumpUntil(
        () => map.controller.style != oldStyle,
        reason: () => 'the new style did not load',
      );
      await expectShown(shown: true);
      expect(map.style.globalState, {'show': true, 'radius': 40});

      // A value removed with a style switch goes back to the default of the
      // new style, also where the map keeps global state across styles.
      final secondStyle = map.style;
      await map.setOptions(_options());
      await map.pumpUntil(
        () => map.controller.style != secondStyle,
        reason: () => 'the third style did not load',
      );
      await expectShown(shown: false);
      expect(map.style.globalState, {'show': false, 'radius': 40});
    });

    testWidgets('reads and changes the light', (tester) async {
      final map = await pumpMap(tester, options: _options());
      final light = map.style.light;
      expect(light.anchor, const Literal(LightAnchor.map));
      expect(light.intensity, const Literal(0.3));
      expect(light.color, const Literal(Color(0xFFFFFFFF)));
      light
        ..intensity = const .literal(0.8)
        ..color = const .literal(Color(0xFFFF0000))
        ..position = const .literal([1.5, 90, 80])
        ..colorTransition = const StyleTransition(duration: Duration.zero);
      expect(light.intensity, const Literal(0.8));
      // Back to the defaults, which the map gets explicitly.
      light
        ..intensity = null
        ..colorTransition = null;
      expect(light.intensity, const Literal(0.5));
      await map.waitForLatestFrame();
      expect(map.events.whereType<MapEventError>(), isEmpty);
    });

    testWidgets('the style transition times paint changes', (tester) async {
      final map = await pumpMap(tester, options: _options());
      expect(
        map.style.transition,
        const StyleTransition(
          duration: Duration(milliseconds: 500),
          delay: Duration(milliseconds: 10),
        ),
      );
      await map.setOptions(_options(globalState: {'show': true}));
      final layer = map.style.layers['points']! as CircleStyleLayer;
      layer.radius = const .literal(40);
      final beside = map.center + const Offset(25, 0);
      await map.waitForFeatures(beside, (features) => features.isNotEmpty);

      // A transition that is far from done keeps the circle large, see the
      // transition test of the layers.
      map.style.transition = const StyleTransition(
        duration: Duration(minutes: 1),
      );
      layer.radius = const .literal(10);
      await Future<void>.delayed(const Duration(seconds: 1));
      await map.waitForFeatures(beside, (features) => features.isNotEmpty);
      expect(
        map.style.transition,
        const StyleTransition(duration: Duration(minutes: 1)),
      );

      map.style.transition = const StyleTransition(duration: Duration.zero);
      layer.radius = const .literal(10.5);
      await map.waitForFeatures(beside, (features) => features.isEmpty);
    });
  });
}
