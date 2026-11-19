part of 'source.dart';

/// A feature of a source, whose feature state [StyleSources.setFeatureState]
/// sets.
///
/// The feature needs an id: the `id` of a GeoJSON feature, or the id of a
/// feature in a vector tile. On web, the ids of GeoJSON features must be
/// non-negative integers.
///
/// {@category Style}
/// {@subCategory Style Sources}
@immutable
final class FeatureRef {
  /// Refers to the feature [id] of the source [sourceId]. A vector source
  /// needs the [sourceLayer] of the feature; other sources take none.
  const FeatureRef({
    required this.sourceId,
    required this.id,
    this.sourceLayer,
  });

  /// Refers to the source feature of [feature], as a query or a layer event
  /// reports it.
  ///
  /// Fails with an [ArgumentError] if [feature] has no id or no source.
  factory FeatureRef.of(RenderedFeature feature) {
    final id = feature.id;
    final sourceId = feature.sourceId;
    if (id == null) {
      throw ArgumentError.value(feature, 'feature', 'The feature has no id');
    }
    if (sourceId == null) {
      throw ArgumentError.value(
        feature,
        'feature',
        'The feature has no source',
      );
    }
    return FeatureRef(
      sourceId: sourceId,
      id: id,
      sourceLayer: switch (feature.sourceLayer) {
        '' => null,
        final layer => layer,
      },
    );
  }

  /// The id of the source.
  final String sourceId;

  /// The layer of a vector source that holds the feature, or null for other
  /// sources.
  final String? sourceLayer;

  /// The id of the feature, a number or a string.
  final Object id;

  @override
  bool operator ==(Object other) =>
      other is FeatureRef &&
      sourceId == other.sourceId &&
      sourceLayer == other.sourceLayer &&
      id == other.id;

  @override
  int get hashCode => Object.hash(sourceId, sourceLayer, id);

  @override
  String toString() =>
      'FeatureRef($sourceId${sourceLayer == null ? '' : '/$sourceLayer'}, '
      '$id)';
}
