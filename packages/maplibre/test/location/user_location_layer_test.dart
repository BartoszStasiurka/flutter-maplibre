import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../shared/mocks.dart';
import '../shared/ui_app.dart';

const _camera = CameraPosition(
  center: Geographic(lon: 0, lat: 0),
  zoom: 10,
  bearing: 30,
  pitch: 0,
);

void main() {
  setUpAll(() {
    registerFallbackValue(const CameraUpdate.position());
    registerFallbackValue(const CameraAnimation.ease());
    registerFallbackValue(const Geographic(lon: 0, lat: 0));
  });

  group('UserLocationLayer', () {
    late MockMapController controller;
    late StreamController<UserLocation> locations;
    late List<UserLocationTracking> trackingChanges;

    setUp(() {
      controller = MockMapController();
      locations = StreamController<UserLocation>();
      trackingChanges = [];
      when(
        () =>
            controller.animateCamera(any(), animation: any(named: 'animation')),
      ).thenAnswer((_) async => CameraAnimationResult.completed);
    });

    tearDown(() => locations.close());

    Future<void> pump(
      WidgetTester tester, {
      UserLocationTracking tracking = UserLocationTracking.none,
      double? trackingZoom,
      UserLocationStyle style = const UserLocationStyle(),
      LayerAnchor anchor = const LayerAnchor.top(),
      ValueChanged<UserLocation>? onClick,
    }) => tester.pumpWidget(
      App(
        camera: _camera,
        controller: controller,
        children: [
          UserLocationLayer(
            locations: locations.stream,
            tracking: tracking,
            trackingZoom: trackingZoom,
            onTrackingChanged: trackingChanges.add,
            style: style,
            anchor: anchor,
            onClick: onClick,
          ),
        ],
      ),
    );

    Future<void> add(WidgetTester tester, UserLocation location) async {
      locations.add(location);
      await tester.pump();
    }

    testWidgets('does not move the camera without tracking', (tester) async {
      await pump(tester);
      await add(
        tester,
        const UserLocation(position: Geographic(lon: 1, lat: 2)),
      );
      verifyNever(
        () =>
            controller.animateCamera(any(), animation: any(named: 'animation')),
      );
    });

    testWidgets('tracks the position, zooming once', (tester) async {
      await pump(
        tester,
        tracking: UserLocationTracking.position,
        trackingZoom: 15,
      );
      await add(
        tester,
        const UserLocation(position: Geographic(lon: 1, lat: 2), heading: 90),
      );
      await add(
        tester,
        const UserLocation(position: Geographic(lon: 3, lat: 4), heading: 90),
      );
      const duration = Duration(milliseconds: 500);
      verifyInOrder([
        () => controller.animateCamera(
          const CameraUpdate.position(
            center: Geographic(lon: 1, lat: 2),
            zoom: 15,
          ),
          animation: const CameraAnimation.fly(duration: duration),
        ),
        () => controller.animateCamera(
          const CameraUpdate.position(center: Geographic(lon: 3, lat: 4)),
          animation: const CameraAnimation.fly(duration: duration),
        ),
      ]);
    });

    testWidgets('tracks the heading', (tester) async {
      await pump(tester, tracking: UserLocationTracking.positionAndHeading);
      await add(
        tester,
        const UserLocation(position: Geographic(lon: 1, lat: 2), heading: 90),
      );
      verify(
        () => controller.animateCamera(
          const CameraUpdate.position(
            center: Geographic(lon: 1, lat: 2),
            bearing: 90,
          ),
          animation: any(named: 'animation'),
        ),
      ).called(1);
    });

    testWidgets('moves to the last location when tracking starts', (
      tester,
    ) async {
      await pump(tester);
      await add(
        tester,
        const UserLocation(position: Geographic(lon: 1, lat: 2)),
      );
      await pump(tester, tracking: UserLocationTracking.position);
      verify(
        () => controller.animateCamera(
          const CameraUpdate.position(center: Geographic(lon: 1, lat: 2)),
          animation: any(named: 'animation'),
        ),
      ).called(1);
    });

    MapPlugin plugin(WidgetTester tester) => tester.widget(
      find.descendant(
        of: find.byType(UserLocationLayer),
        matching: find.byType(MapPlugin),
      ),
    );

    testWidgets('a gesture stops the tracking, a camera call does not', (
      tester,
    ) async {
      await pump(tester, tracking: UserLocationTracking.position);
      final onCameraMoveStart = plugin(tester).onCameraMoveStart!;
      onCameraMoveStart(
        const MapEventCameraMoveStart(reason: CameraChangeReason.programmatic),
      );
      expect(trackingChanges, isEmpty);
      onCameraMoveStart(
        const MapEventCameraMoveStart(reason: CameraChangeReason.gesture),
      );
      expect(trackingChanges, [UserLocationTracking.none]);
      clearInteractions(controller);
      await add(
        tester,
        const UserLocation(position: Geographic(lon: 1, lat: 2)),
      );
      verifyNever(
        () =>
            controller.animateCamera(any(), animation: any(named: 'animation')),
      );
    });

    testWidgets('hands the plugin the layers of the location', (tester) async {
      await pump(tester);
      expect(plugin(tester).layers, isEmpty);
      await add(
        tester,
        const UserLocation(position: Geographic(lon: 1, lat: 2), accuracy: 10),
      );
      final layers = plugin(tester).layers;
      // The accuracy circle and the dot.
      expect(layers, hasLength(2));
      // A rebuild keeps the layers while the location stays.
      await tester.pump();
      expect(plugin(tester).layers, same(layers));

      await pump(tester, style: const UserLocationStyle(showAccuracy: false));
      expect(plugin(tester).layers, hasLength(1));
    });

    testWidgets('keeps the layers when the parent passes a new onClick', (
      tester,
    ) async {
      final clicks = <UserLocation>[];
      const location = UserLocation(position: Geographic(lon: 1, lat: 2));
      // A closure, as apps write it inline, is a new callback per build.
      // ignore: unnecessary_lambdas
      await pump(tester, onClick: (location) => clicks.add(location));
      await add(tester, location);
      final layers = plugin(tester).layers;
      // ignore: unnecessary_lambdas
      await pump(tester, onClick: (location) => clicks.add(location));
      expect(plugin(tester).layers, same(layers));

      layers.single.onClick!(
        const LayerFeatureEvent(
          index: 0,
          feature: Feature(geometry: Point(Geographic(lon: 1, lat: 2))),
          geometry: Point(Geographic(lon: 1, lat: 2)),
          point: Geographic(lon: 1, lat: 2),
          screenPoint: Offset.zero,
        ),
      );
      expect(clicks, [location]);

      await pump(tester);
      expect(plugin(tester).layers.single.onClick, isNull);
    });

    testWidgets('places the layers at the anchor', (tester) async {
      await pump(tester, anchor: const LayerAnchor.below('labels'));
      await add(
        tester,
        const UserLocation(position: Geographic(lon: 1, lat: 2), accuracy: 10),
      );
      expect(
        plugin(tester).layers.map((layer) => layer.anchor),
        everyElement(const LayerAnchor.below('labels')),
      );
    });

    testWidgets('lets pointers through to the map', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        App(
          camera: _camera,
          controller: controller,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand(),
            ),
            UserLocationLayer(locations: locations.stream),
          ],
        ),
      );
      await tester.tapAt(const Offset(400, 300));
      expect(taps, 1);
    });
  });
}
