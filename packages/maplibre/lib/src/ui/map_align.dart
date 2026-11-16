import 'package:flutter/widgets.dart';
import 'package:maplibre/maplibre.dart';

/// Stacks widgets of [MapLibreMap.children] at one [alignment] of the map,
/// so that several of them share a corner or an edge without overlapping.
///
/// A [MapAlign] places the [MapAlignItem]s in it: its [alignment],
/// [padding] and [spacing] replace the alignment and padding of each item.
/// The widgets of this package, such as `MapCompass`, `MapControlButtons`,
/// `MapScalebar` and `SourceAttribution`, are such items: alone they place
/// themselves, inside a [MapAlign] it places them.
///
/// ```dart
/// MapLibreMap(
///   children: const [
///     MapAlign(
///       alignment: Alignment.topRight,
///       children: [MapCompass(), MapControlButtons()],
///     ),
///     MapAlign(
///       alignment: Alignment.bottomLeft,
///       children: [MapScalebar()],
///     ),
///   ],
/// )
/// ```
///
/// Widgets of plugins can do the same with [MapAlignItem]. Each child
/// gets its own size. Wrap a child that expands, such as an [Align], in a
/// [Flexible], so that it takes the space that the others leave.
///
/// {@category UI}
class MapAlign extends StatelessWidget {
  /// Stacks [children] at [alignment].
  const MapAlign({
    required this.alignment,
    required this.children,
    this.direction = Axis.vertical,
    this.spacing = 8,
    this.padding = const EdgeInsets.all(10),
    super.key,
  });

  /// Where the widgets go on the map.
  final Alignment alignment;

  /// The widgets, from the top or from the left.
  final List<Widget> children;

  /// Whether the widgets are stacked from top to bottom, the default, or
  /// placed side by side.
  final Axis direction;

  /// The space between two widgets, in logical pixels.
  final double spacing;

  /// The space between the widgets and the edges of the map, inside the
  /// safe area of the screen.
  final EdgeInsets padding;

  /// The [alignment] of the closest [MapAlign] around [context], or null if
  /// there is none. A widget that places itself on the map only does so
  /// while this is null.
  static Alignment? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MapAlignScope>()?.alignment;

  @override
  Widget build(BuildContext context) {
    final across = switch (direction) {
      Axis.vertical => alignment.x,
      Axis.horizontal => alignment.y,
    };
    return SafeArea(
      child: Padding(
        padding: padding,
        child: Align(
          alignment: alignment,
          child: _MapAlignScope(
            alignment: alignment,
            child: Flex(
              direction: direction,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: across < 0
                  ? CrossAxisAlignment.start
                  : across > 0
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.center,
              spacing: spacing,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _MapAlignScope extends InheritedWidget {
  const _MapAlignScope({required this.alignment, required super.child});

  final Alignment alignment;

  @override
  bool updateShouldNotify(_MapAlignScope oldWidget) =>
      alignment != oldWidget.alignment;
}

/// Places [child] at [alignment] with [padding] inside the safe area of the
/// screen, unless a [MapAlign] around it places it: then it shows [child] as
/// it is, with the alignment, padding and spacing of that [MapAlign].
///
/// The widgets of this package, such as `MapCompass`, use it, so that they
/// can stand alone in [MapLibreMap.children] or be grouped in a [MapAlign].
/// Use it for the widgets of plugins the same way.
///
/// ```dart
/// class MyBadge extends StatelessWidget {
///   const MyBadge({super.key});
///
///   @override
///   Widget build(BuildContext context) => const MapAlignItem(
///     alignment: Alignment.bottomRight,
///     child: ColoredBox(
///       color: Color(0xFF3366FF),
///       child: SizedBox.square(dimension: 24),
///     ),
///   );
/// }
/// ```
///
/// {@category UI}
class MapAlignItem extends StatelessWidget {
  /// Places [child] at [alignment] unless a [MapAlign] places it.
  const MapAlignItem({
    required this.alignment,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    super.key,
  });

  /// Where [child] goes when no [MapAlign] places it.
  final Alignment alignment;

  /// The space around [child] when no [MapAlign] places it.
  final EdgeInsets padding;

  /// The widget to place.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MapAlign.maybeOf(context) != null) return child;
    // The SafeArea keeps the widget visible on screens with rounded corners
    // and next to system bars.
    return SafeArea(
      child: Container(alignment: alignment, padding: padding, child: child),
    );
  }
}
