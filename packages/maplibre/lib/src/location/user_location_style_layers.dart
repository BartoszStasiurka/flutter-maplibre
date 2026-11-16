import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:maplibre/maplibre.dart';

/// The circumference of the earth at the equator in meters, as the map uses
/// it for its pixel sizes.
const _earthCircumference = 40075016.686;

/// The size of a map tile in logical pixels, which zoom 0 shows the world
/// in, on every platform.
const _tileSize = 512.0;

/// The highest zoom of the accuracy radius, where the radius stops
/// growing. Layers can't show above it on web.
const _maxZoom = 24.0;

/// The logical size of the heading image, for a dot of [_headingRadius].
const _headingSize = 64.0;

/// The dot radius that the heading image is drawn for. Other radii scale it.
const _headingRadius = 8.0;

/// The pixel ratio that the heading image is drawn at.
const _headingPixelRatio = 3.0;

/// The layers that show [location] in [style]: the accuracy
/// circle, the heading cone and the dot or icon, from the bottom. Each is a
/// type of its own, so that the map keeps their style layers when another
/// location comes.
///
/// The accuracy and the heading are properties of the feature, which the
/// style layers read, so a new location only changes data and the style
/// layers stay the same.
///
/// [headingImage] is the PNG of the heading cone from [drawHeadingImage], or
/// null while it is drawn, which leaves the heading out. An icon that turns
/// with the heading shows it already, so it leaves the cone out too.
///
/// [onClick] goes to the dot or the icon. Pass the same callback for every
/// location, such as a method tear-off, so that the layers compare equal
/// while nothing else changes.
List<Layer> userLocationStyleLayers({
  required UserLocation location,
  required UserLocationStyle style,
  LayerAnchor anchor = const LayerAnchor.top(),
  LayerFeatureCallback? onClick,
  Uint8List? headingImage,
}) {
  final UserLocationStyle(:color, :radius, :icon, :rotateIcon) = style;
  final accuracy = location.accuracy;
  final heading = location.heading;
  final points = [
    Feature(
      geometry: Point(location.position),
      properties: {
        _accuracyProperty: accuracy == null
            ? 0
            : accuracyPixels(accuracy, location.position.lat),
        _headingProperty: heading ?? 0,
      },
    ),
  ];
  final iconShowsHeading = icon != null && rotateIcon;
  return [
    if (style.showAccuracy && accuracy != null && accuracy > 0)
      _AccuracyLayer(anchor: anchor, points: points, color: color),
    if (style.showHeading &&
        !iconShowsHeading &&
        heading != null &&
        headingImage != null)
      _HeadingLayer(
        anchor: anchor,
        points: points,
        icon: MarkerIcon.bytes(headingImage, pixelRatio: _headingPixelRatio),
        size: radius / _headingRadius,
        rotates: true,
        flat: true,
      ),
    if (icon != null)
      _IconLayer(
        anchor: anchor,
        points: points,
        icon: icon,
        size: 1,
        rotates: rotateIcon,
        flat: false,
        onClick: onClick,
      )
    else
      _DotLayer(
        anchor: anchor,
        points: points,
        radius: radius,
        color: color,
        onClick: onClick,
      ),
  ];
}

/// The feature property of the accuracy radius in pixels at zoom 0.
const _accuracyProperty = 'accuracy';

/// The feature property of the heading in degrees.
const _headingProperty = 'heading';

/// The radius in pixels at zoom 0 of [accuracy] meters at the latitude
/// [lat].
double accuracyPixels(double accuracy, double lat) {
  final metersPerPixel =
      _earthCircumference * cos(lat * pi / 180).abs() / _tileSize;
  return accuracy / max(metersPerPixel, 1e-6);
}

/// The circle radius of the accuracy at every zoom, from the feature's
/// radius at zoom 0: the radius doubles with each zoom level.
final Expression<num> accuracyRadius = Expression.interpolate(
  const .exponential(2),
  .zoom(),
  {
    0: Expression.get(_accuracyProperty).asNumber(),
    _maxZoom: Expression.product([
      Expression.get(_accuracyProperty).asNumber(),
      Expression.literal(pow(2, _maxZoom)),
    ]),
  },
);

/// The heading of the feature, in degrees from north.
final Expression<num> _headingRotation = Expression.get(_headingProperty)
    .asNumber();

/// Draws the heading cone in [color] as a PNG: a cone of 60 degrees that
/// points up from the center of the image, fading out.
Future<Uint8List> drawHeadingImage(Color color) async {
  const pixels = _headingSize * _headingPixelRatio;
  const center = Offset(pixels / 2, pixels / 2);
  const length = pixels / 2;
  final recorder = ui.PictureRecorder();
  final rect = Rect.fromCircle(center: center, radius: length);
  final cone = Path()
    ..moveTo(center.dx, center.dy)
    ..arcTo(rect, -pi / 2 - pi / 6, pi / 3, false)
    ..close();
  Canvas(recorder).drawPath(
    cone,
    Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.5), color.withValues(alpha: 0)],
      ).createShader(rect),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(pixels.toInt(), pixels.toInt());
  picture.dispose();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// A layer of points with the given style, for the marker's own layers.
abstract class _MarkerLayer extends Layer<Feature<Point>> {
  const _MarkerLayer({
    required super.anchor,
    required List<Feature<Point>> points,
    super.onClick,
  }) : super(list: points);
}

/// The accuracy circle, which lies flat on the map.
final class _AccuracyLayer extends _MarkerLayer {
  const _AccuracyLayer({
    required super.anchor,
    required super.points,
    required this.color,
  });

  final Color color;

  @override
  StyleLayer createStyleLayer({required String id, required String sourceId}) =>
      CircleStyleLayer(
        id: id,
        sourceId: sourceId,
        maxZoom: maxZoom,
        radius: accuracyRadius,
        color: .literal(color.withValues(alpha: 0.15)),
        strokeWidth: const .literal(1),
        strokeColor: .literal(color.withValues(alpha: 0.4)),
        pitchAlignment: const .literal(CirclePitchAlignment.map),
        pitchScale: const .literal(CirclePitchScale.map),
      );

  @override
  bool operator ==(Object other) =>
      super == other && other is _AccuracyLayer && color == other.color;

  @override
  int get hashCode => Object.hash(super.hashCode, color);
}

/// The dot, which faces the viewer.
final class _DotLayer extends _MarkerLayer {
  const _DotLayer({
    required super.anchor,
    required super.points,
    required this.radius,
    required this.color,
    super.onClick,
  });

  final double radius;
  final Color color;

  @override
  StyleLayer createStyleLayer({required String id, required String sourceId}) =>
      CircleStyleLayer(
        id: id,
        sourceId: sourceId,
        maxZoom: maxZoom,
        radius: .literal(radius),
        color: .literal(color),
        strokeWidth: const .literal(2),
        strokeColor: const .literal(Color(0xFFFFFFFF)),
      );

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is _DotLayer &&
      radius == other.radius &&
      color == other.color &&
      onClick == other.onClick;

  @override
  int get hashCode => Object.hash(super.hashCode, radius, color, onClick);
}

/// An image at the location, the heading cone or the icon that replaces the
/// dot. It turns with the map to the heading of the location while it
/// [rotates], or else stays upright on the screen. A [flat] image lies on
/// the map.
class _IconLayer extends _MarkerLayer {
  const _IconLayer({
    required super.anchor,
    required super.points,
    required this.icon,
    required this.size,
    required this.rotates,
    required this.flat,
    super.onClick,
  });

  @override
  final MarkerIcon icon;
  final double size;
  final bool rotates;
  final bool flat;

  @override
  StyleLayer createStyleLayer({required String id, required String sourceId}) =>
      SymbolStyleLayer(
        id: id,
        sourceId: sourceId,
        maxZoom: maxZoom,
        iconSize: .literal(size),
        iconRotate: rotates ? _headingRotation : null,
        iconRotationAlignment: .literal(
          rotates ? IconRotationAlignment.map : IconRotationAlignment.viewport,
        ),
        iconPitchAlignment: .literal(
          flat ? IconPitchAlignment.map : IconPitchAlignment.viewport,
        ),
        // The location never hides labels and is never hidden by them.
        iconAllowOverlap: const .literal(true),
        iconIgnorePlacement: const .literal(true),
      );

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is _IconLayer &&
      size == other.size &&
      rotates == other.rotates &&
      flat == other.flat &&
      onClick == other.onClick;

  @override
  int get hashCode => Object.hash(super.hashCode, size, rotates, flat, onClick);
}

/// The heading cone, an [_IconLayer] of its own type.
///
/// The annotation manager matches the layers of a new list to its current
/// ones by their type, not by an id, as these layers have none. A type of
/// its own keeps the cone matched to the cone, and the icon to the icon, on
/// every location, so that they are updated instead of replaced.
final class _HeadingLayer extends _IconLayer {
  const _HeadingLayer({
    required super.anchor,
    required super.points,
    required super.icon,
    required super.size,
    required super.rotates,
    required super.flat,
  });
}
