import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';
import 'package:maplibre/src/location/user_location_style_layers.dart';

const _color = Color(0xFF1A73E8);

List<StyleLayer> _styleLayers(
  UserLocation location, {
  UserLocationStyle style = const UserLocationStyle(),
  Uint8List? headingImage,
}) => [
  for (final layer in userLocationStyleLayers(
    location: location,
    style: style,
    headingImage: headingImage,
  ))
    layer.createStyleLayer(id: 'layer', sourceId: 'source'),
];

void main() {
  const position = Geographic(lon: 10, lat: 60);

  test('draws the accuracy, the heading and the dot, from the bottom', () {
    final layers = _styleLayers(
      const UserLocation(position: position, accuracy: 20, heading: 90),
      headingImage: Uint8List(1),
    );
    expect(layers.map((layer) => layer.type), ['circle', 'symbol', 'circle']);
    final accuracy = layers[0] as CircleStyleLayer;
    expect(
      accuracy.pitchAlignment,
      const Expression.literal(CirclePitchAlignment.map),
    );
    expect(accuracy.pitchScale, const Expression.literal(CirclePitchScale.map));
    final heading = layers[1] as SymbolStyleLayer;
    expect(heading.iconRotate.toJson(), [
      'number',
      ['get', 'heading'],
    ]);
    expect(
      heading.iconPitchAlignment,
      const Expression.literal(IconPitchAlignment.map),
    );
    expect(heading.iconAllowOverlap, const Expression.literal(true));
    final dot = layers[2] as CircleStyleLayer;
    expect(dot.radius, const Expression.literal(8));
    expect(dot.color, const Expression.literal(_color));
  });

  test('leaves out what the location does not know', () {
    final layers = _styleLayers(
      const UserLocation(position: position),
      headingImage: Uint8List(1),
    );
    expect(layers.single, isA<CircleStyleLayer>());
  });

  test('leaves out the heading until its image is drawn', () {
    final layers = _styleLayers(
      const UserLocation(position: position, heading: 90),
    );
    expect(layers.single, isA<CircleStyleLayer>());
  });

  test('leaves out what the style hides', () {
    final layers = _styleLayers(
      const UserLocation(position: position, accuracy: 20, heading: 90),
      style: const UserLocationStyle(showAccuracy: false, showHeading: false),
      headingImage: Uint8List(1),
    );
    expect(layers.single, isA<CircleStyleLayer>());
  });

  test('an icon replaces the dot and turns with the heading', () {
    const icon = MarkerIcon.named('arrow');
    List<Layer> layers({required bool rotateIcon}) => userLocationStyleLayers(
      location: const UserLocation(position: position, heading: 45),
      style: UserLocationStyle(
        icon: icon,
        rotateIcon: rotateIcon,
        showHeading: false,
      ),
    );
    final layer = layers(rotateIcon: true).single;
    expect(layer.icon, icon);
    final symbol = layer.createStyleLayer(
      id: 'p-icon',
      sourceId: 'p-icon',
    ) as SymbolStyleLayer;
    expect(symbol.iconRotate, isNotNull);
    expect(
      symbol.iconRotationAlignment,
      const Expression.literal(IconRotationAlignment.map),
    );
    final upright = layers(
      rotateIcon: false,
    ).single.createStyleLayer(id: 'p', sourceId: 'p') as SymbolStyleLayer;
    expect(upright.iconRotate, const Expression.literal(0));
    expect(
      upright.iconRotationAlignment,
      const Expression.literal(IconRotationAlignment.viewport),
    );
  });

  test('a turning icon shows the heading instead of the cone', () {
    const icon = MarkerIcon.named('arrow');
    List<String> types({required bool rotateIcon}) => [
      for (final layer in userLocationStyleLayers(
        location: const UserLocation(position: position, heading: 45),
        style: UserLocationStyle(icon: icon, rotateIcon: rotateIcon),
        headingImage: Uint8List(1),
      ))
        layer.createStyleLayer(id: 'l', sourceId: 's').type,
    ];
    expect(types(rotateIcon: true), ['symbol']);
    expect(types(rotateIcon: false), ['symbol', 'symbol']);
  });

  test('the dot or the icon gets the click callback', () {
    void onClick(LayerFeatureEvent event) {}
    for (final style in const [
      UserLocationStyle(),
      UserLocationStyle(icon: MarkerIcon.named('arrow')),
    ]) {
      final layers = userLocationStyleLayers(
        location: const UserLocation(position: position, accuracy: 20),
        style: style,
        onClick: onClick,
      );
      expect(layers.first.onClick, isNull);
      expect(layers.last.onClick, onClick);
    }
  });

  test('places every layer at the anchor', () {
    final layers = userLocationStyleLayers(
      location: const UserLocation(
        position: position,
        accuracy: 20,
        heading: 90,
      ),
      style: const UserLocationStyle(),
      anchor: const LayerAnchor.below('labels'),
      headingImage: Uint8List(1),
    );
    expect(layers, hasLength(3));
    expect(
      layers.map((layer) => layer.anchor),
      everyElement(const LayerAnchor.below('labels')),
    );
  });

  test('draws the heading cone as a PNG', () async {
    final png = await drawHeadingImage(_color);
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
  });

  test('UserLocationStyle asserts a positive radius', () {
    expect(() => UserLocationStyle(radius: -1), throwsAssertionError);
  });

  test('the accuracy radius is in meters at every zoom', () {
    // At 60 degrees, a pixel at zoom 0 is half the equator's pixel.
    const metersPerPixel = 40075016.686 / 512 / 2;
    expect(accuracyPixels(metersPerPixel * 10, 60), closeTo(10, 1e-6));
    final stops = (accuracyRadius.toJson()! as List).skip(3).toList();
    expect(stops[0], 0);
    expect(stops[1], [
      'number',
      ['get', 'accuracy'],
    ]);
    expect(stops[2], 24);
    expect(stops[3], [
      '*',
      [
        'number',
        ['get', 'accuracy'],
      ],
      pow(2, 24),
    ]);
  });

  test('a new location changes only the data of the layers', () {
    List<Layer> layers(UserLocation location) => userLocationStyleLayers(
      location: location,
      style: const UserLocationStyle(),
      headingImage: Uint8List(1),
    );
    final first = layers(
      const UserLocation(position: position, accuracy: 20, heading: 90),
    );
    final second = layers(
      const UserLocation(
        position: Geographic(lon: 11, lat: 61),
        accuracy: 50,
        heading: 180,
      ),
    );
    for (var i = 0; i < first.length; i++) {
      expect(
        first[i].createStyleLayer(id: 'l', sourceId: 's').toJson(),
        second[i].createStyleLayer(id: 'l', sourceId: 's').toJson(),
      );
    }
    final properties = second.first.list.single.properties;
    expect(properties['heading'], 180);
    expect(
      properties['accuracy'] as num,
      closeTo(accuracyPixels(50, 61), 1e-9),
    );
  });

  test('UserLocationStyle copies and compares by value', () {
    const style = UserLocationStyle();
    final copy = style.copyWith(radius: 12, showHeading: false);
    expect(copy.radius, 12);
    expect(copy.showHeading, isFalse);
    expect(copy.color, style.color);
    expect(copy, const UserLocationStyle(radius: 12, showHeading: false));
    expect(
      copy.hashCode,
      const UserLocationStyle(radius: 12, showHeading: false).hashCode,
    );
    expect(copy, isNot(style));
    expect(style.toString(), contains('UserLocationStyle'));
  });
}
