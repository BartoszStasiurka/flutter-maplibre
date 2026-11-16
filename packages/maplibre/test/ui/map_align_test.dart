import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../shared/mocks.dart';
import '../shared/ui_app.dart';

void main() {
  group('MapAlign', () {
    const camera = CameraPosition(
      center: Geographic(lon: 0, lat: 0),
      zoom: 5,
      bearing: 90,
      pitch: 0,
    );

    late MockMapController controller;
    setUp(() {
      controller = MockMapController();
      when(controller.getCamera).thenReturn(camera);
    });

    Future<void> pump(WidgetTester tester, List<Widget> children) async {
      tester.view
        ..physicalSize = const Size(800, 600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        App(camera: camera, controller: controller, children: children),
      );
    }

    testWidgets('stacks its widgets at its alignment', (tester) async {
      await pump(tester, const [
        MapAlign(
          alignment: Alignment.topRight,
          children: [MapCompass(), MapControlButtons()],
        ),
      ]);
      final compass = tester.getRect(find.bySemanticsLabel('Compass'));
      final zoomIn = tester.getRect(find.bySemanticsLabel('Zoom in'));
      // The default padding, without the own padding of the widgets.
      expect(compass.right, 790);
      expect(compass.top, 10);
      expect(zoomIn.right, 790);
      expect(zoomIn.top, greaterThan(compass.bottom));
      expect(zoomIn.top - compass.bottom, lessThan(20));
    });

    testWidgets('widgets outside place themselves', (tester) async {
      await pump(tester, const [
        MapCompass(alignment: Alignment.topLeft, padding: EdgeInsets.all(20)),
      ]);
      final compass = tester.getRect(find.bySemanticsLabel('Compass'));
      expect(compass.topLeft, const Offset(20, 20));
    });

    testWidgets('places side by side along the bottom', (tester) async {
      await pump(tester, const [
        MapAlign(
          alignment: Alignment.bottomLeft,
          direction: Axis.horizontal,
          padding: EdgeInsets.zero,
          spacing: 4,
          children: [
            SizedBox(key: ValueKey('a'), width: 10, height: 10),
            SizedBox(key: ValueKey('b'), width: 10, height: 20),
          ],
        ),
      ]);
      final a = tester.getRect(find.byKey(const ValueKey('a')));
      final b = tester.getRect(find.byKey(const ValueKey('b')));
      expect(a.left, 0);
      expect(b.left, 14);
      expect(a.bottom, 600);
      expect(b.bottom, 600);
    });

    testWidgets('lays out a child that expands in a Flexible', (tester) async {
      await pump(tester, const [
        MapAlign(
          alignment: Alignment.topLeft,
          children: [
            SizedBox(key: ValueKey('a'), width: 10, height: 10),
            Flexible(
              child: Align(
                child: SizedBox(key: ValueKey('b'), width: 10, height: 10),
              ),
            ),
          ],
        ),
      ]);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('b')), findsOneWidget);
    });

    testWidgets('gives each child its own size', (tester) async {
      tester.view
        ..physicalSize = const Size(400, 300)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        App(
          camera: camera,
          controller: controller,
          children: const [
            MapAlign(
              alignment: Alignment.topLeft,
              children: [
                SizedBox(key: ValueKey('tall'), width: 10, height: 150),
                SizedBox(width: 10, height: 20),
                SizedBox(width: 10, height: 20),
              ],
            ),
          ],
        ),
      );
      expect(tester.getSize(find.byKey(const ValueKey('tall'))).height, 150);
    });

    testWidgets('an item places itself alone and follows a MapAlign', (
      tester,
    ) async {
      const item = MapAlignItem(
        alignment: Alignment.bottomRight,
        padding: EdgeInsets.all(20),
        child: SizedBox(key: ValueKey('item'), width: 10, height: 10),
      );
      await pump(tester, const [item]);
      expect(
        tester.getRect(find.byKey(const ValueKey('item'))).bottomRight,
        const Offset(780, 580),
      );
      await pump(tester, const [
        MapAlign(alignment: Alignment.topLeft, children: [item]),
      ]);
      expect(
        tester.getRect(find.byKey(const ValueKey('item'))).topLeft,
        const Offset(10, 10),
      );
    });

    testWidgets('maybeOf tells the widgets inside', (tester) async {
      Alignment? inside;
      Alignment? outside;
      await pump(tester, [
        MapAlign(
          alignment: Alignment.centerLeft,
          children: [
            Builder(
              builder: (context) {
                inside = MapAlign.maybeOf(context);
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        Builder(
          builder: (context) {
            outside = MapAlign.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      ]);
      expect(inside, Alignment.centerLeft);
      expect(outside, isNull);
    });
  });
}
