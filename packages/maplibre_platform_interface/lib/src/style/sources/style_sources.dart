part of 'source.dart';

/// The sources of a map style.
///
/// Reading is synchronous: the collection is filled once when the style loads
/// and follows every change made through it. Sources are immutable, so an
/// update replaces the object in this collection. Changes apply to the
/// collection at once and reach the map in the order they were made.
///
/// It notifies its listeners when a source is added or removed, or the
/// TileJSON of a source changed what it says, such as its attribution, but
/// not when the data of a source changes.
///
/// Setting a new style detaches the collection, since the map's source
/// commands reach that style from then on. It still reads the sources of the
/// style on screen until that one loads, but takes no change.
///
/// {@category Style}
/// {@subCategory Style Sources}
final class StyleSources extends Iterable<Source> implements Listenable {
  /// Creates an empty collection. Platforms create it, on their [StyleBackend]
  /// and the `layers` of their style, which [remove] checks.
  StyleSources(this._backend, {this._layers});

  final StyleBackend _backend;
  final Iterable<StyleLayer> Function()? _layers;

  /// The sources by id, in the order of the style.
  final _sources = <String, Source>{};
  final ValueNotifier<int> _changes = ValueNotifier(0);

  @override
  void addListener(VoidCallback listener) => _changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);

  /// The source JSON of the sources as they were specified, without what a
  /// TileJSON resource added: an update must not carry that over.
  final _specifications = <String, Map<String, Object?>>{};

  /// The feature state that was set, by source id, source layer (empty for
  /// sources without layers) and feature id. The map keeps nothing else, so
  /// this is all of it.
  final _featureStates =
      <String, Map<String, Map<Object, Map<String, Object?>>>>{};

  var _replaced = false;
  var _warnedReplaced = false;

  /// The missing sources that debug builds warned about a feature state
  /// change for.
  final _warnedMissing = <String>{};

  /// The part of the map that owns some of the sources, see
  /// [setStyleSourcesOwner].
  StyleOwner? _styleOwner;

  /// The owned sources that debug builds warned about.
  final _warnedOwned = <String>{};

  /// A source that another part of the map owns, such as the source of a
  /// layer of [MapLibreMap.layers], gets its data from there, which
  /// overrides other changes, so debug builds warn once.
  void _warnIfOwned(String id) {
    final owner = _styleOwner;
    if (owner == null || owner.isWriting || !owner.ownsSource(id)) return;
    if (!_warnedOwned.add(id)) return;
    if (kDebugMode) {
      debugPrint(
        'maplibre: the source "$id" belongs to ${owner.name}, which '
        'overrides changes made to it here. Change ${owner.name} instead.',
      );
    }
  }

  @override
  Iterator<Source> get iterator => _sources.values.iterator;

  @override
  int get length => _sources.length;

  /// The source [id], or null if the style has none.
  Source? operator [](String id) => _sources[id];

  /// Adds [source].
  ///
  /// The source is in this collection at once. The future completes when the
  /// map took it. If the map rejects it, the future completes with the error
  /// and the source is taken out again.
  ///
  /// Fails with an [ArgumentError] if its id is taken.
  Future<void> add(Source source) async {
    if (_detachedOrWarn()) return;
    if (_sources.containsKey(source.id)) {
      throw ArgumentError.value(
        source.id,
        'source',
        'The id is already in use',
      );
    }
    _sources[source.id] = source;
    if (_isTileSource(source)) _specifications[source.id] = source.toJson()!;
    _changes.value++;
    try {
      await _backend.addSource(source);
    } catch (_) {
      if (identical(_sources[source.id], source)) {
        _sources.remove(source.id);
        _specifications.remove(source.id);
        _changes.value++;
      }
      rethrow;
    }
  }

  /// Removes the source [id]. Removing a source the style doesn't have does
  /// nothing.
  ///
  /// Fails with a [StateError] if layers still use the source: the map would
  /// keep it. Remove them first.
  Future<void> remove(String id) async {
    if (_detachedOrWarn()) return;
    if (!_sources.containsKey(id)) return;
    final users = [
      for (final layer in _layers?.call() ?? const <StyleLayer>[])
        if (_sourceIdOf(layer) == id) layer.id,
    ];
    if (users.isNotEmpty) {
      throw StateError(
        'The source "$id" is in use by the layers ${users.join(', ')}.',
      );
    }
    _sources.remove(id);
    _specifications.remove(id);
    // The map drops the feature state with the source.
    _featureStates.remove(id);
    _changes.value++;
    await _backend.removeSource(id);
  }

  /// Replaces the data of the GeoJSON source [id] with [data].
  ///
  /// The source of a layer of [MapLibreMap.layers] gets its data from that
  /// list: change the list instead.
  Future<void> updateGeoJsonData(String id, GeoJsonData data) async {
    if (_detachedOrWarn()) return;
    _warnIfOwned(id);
    _sources[id] = _sourceOfType<GeoJsonSource>(id)._withData(data);
    await _backend.setGeoJsonData(id, data);
  }

  /// Makes the GeoJSON source [id] load its data from [url].
  ///
  /// The source of a layer of [MapLibreMap.layers] gets its data from that
  /// list: change the list instead.
  Future<void> updateGeoJsonUrl(String id, String url) async {
    if (_detachedOrWarn()) return;
    _warnIfOwned(id);
    _sources[id] = _sourceOfType<GeoJsonSource>(id)._withUrl(url);
    await _backend.setGeoJsonUrl(id, url);
  }

  /// Moves the corners of the image source [id] to [coordinates].
  Future<void> updateImageCoordinates(String id, LngLatQuad coordinates) async {
    if (_detachedOrWarn()) return;
    final source = _sourceOfType<ImageSource>(id);
    _sources[id] = switch (source) {
      ImageSourceUrl(:final url) => ImageSourceUrl(
        id: id,
        url: url,
        coordinates: coordinates,
      ),
      ImageSourceBytes(:final bytes) => ImageSourceBytes(
        id: id,
        bytes: bytes,
        coordinates: coordinates,
      ),
      ImageSourceProvider(:final image) => ImageSourceProvider(
        id: id,
        image: image,
        coordinates: coordinates,
      ),
    };
    await _backend.setImageCoordinates(id, coordinates);
  }

  /// Replaces the tile URLs of the raster, raster DEM or vector source [id].
  ///
  /// A source that had a TileJSON URL uses [tiles] from now on. Not on web,
  /// the layers of the source are removed and added again, which [StyleLayer]
  /// objects don't notice. The feature state of the source is cleared.
  Future<void> updateTiles(String id, List<String> tiles) async {
    if (_detachedOrWarn()) return;
    final specification = {..._tileSpecification(id), 'tiles': tiles}
      ..remove('url');
    _replaceTileSource(id, specification);
    await _backend.setTiles(id, tiles, specification);
  }

  /// Replaces the TileJSON URL of the raster, raster DEM or vector source
  /// [id].
  ///
  /// A source that had tile URLs uses [url] from now on. Not on web, the
  /// layers of the source are removed and added again, which [StyleLayer]
  /// objects don't notice. The feature state of the source is cleared.
  Future<void> updateTileJsonUrl(String id, String url) async {
    if (_detachedOrWarn()) return;
    final specification = {..._tileSpecification(id), 'url': url}
      ..remove('tiles');
    _replaceTileSource(id, specification);
    await _backend.setTileJsonUrl(id, url, specification);
  }

  /// Merges [state] into the feature state of [feature]: its keys replace the
  /// same keys of the feature, and the other keys stay.
  ///
  /// Layers read feature state with the `feature-state` expression
  /// ([Expression.featureState]) in their paint properties, so a change
  /// shows on the next frame without touching the data of the source. Use it
  /// for states such as hover or selection.
  ///
  /// The change reaches the map without waiting, in order with other changes.
  /// The state stays while the source is on the map, also when its data
  /// changes. It goes with the source or the style, and with [updateTiles]
  /// and [updateTileJsonUrl].
  ///
  /// Only GeoJSON and vector sources have feature state. Fails with an
  /// [ArgumentError] if [feature] has no [FeatureRef.sourceLayer] on a vector
  /// source, has one on another source, or is on a source of another type.
  /// If the style has no such source, as when it was removed while the
  /// pointer was still on one of its features, it does nothing, and debug
  /// builds warn once per source.
  void setFeatureState(FeatureRef feature, Map<String, Object?> state) {
    if (_detachedOrWarn()) return;
    final sourceLayer = _featureStateLayer(
      feature.sourceId,
      feature.sourceLayer,
    );
    if (sourceLayer == null) return;
    final features = _featureStates
        .putIfAbsent(feature.sourceId, () => {})
        .putIfAbsent(sourceLayer, () => {});
    final current = features[feature.id] ?? const {};
    features[feature.id] = Map.unmodifiable({...current, ...state});
    _backend.setFeatureState(feature, state);
  }

  /// The feature state of [feature], as [setFeatureState] set it, or an empty
  /// map if it has none or the style has no such source.
  ///
  /// Fails like [setFeatureState] for a wrong [FeatureRef.sourceLayer].
  Map<String, Object?> featureState(FeatureRef feature) {
    final sourceLayer = _featureStateLayer(
      feature.sourceId,
      feature.sourceLayer,
      warn: false,
    );
    if (sourceLayer == null) return const {};
    return _featureStates[feature.sourceId]?[sourceLayer]?[feature.id] ??
        const {};
  }

  /// Removes the key [key] from the feature state of [feature], or all of its
  /// state if [key] is null.
  ///
  /// Fails or does nothing like [setFeatureState].
  void removeFeatureState(FeatureRef feature, {String? key}) {
    if (_detachedOrWarn()) return;
    final sourceLayer = _featureStateLayer(
      feature.sourceId,
      feature.sourceLayer,
    );
    if (sourceLayer == null) return;
    final features = _featureStates[feature.sourceId]?[sourceLayer];
    if (features != null) {
      final rest = key == null
          ? const <String, Object?>{}
          : ({...?features[feature.id]}..remove(key));
      // A feature without state keeps no entry, so hovering over many
      // features doesn't grow the cache.
      if (rest.isEmpty) {
        features.remove(feature.id);
      } else {
        features[feature.id] = Map.unmodifiable(rest);
      }
    }
    _backend.removeFeatureState(
      feature.sourceId,
      sourceLayer: feature.sourceLayer,
      id: feature.id,
      key: key,
    );
  }

  /// Removes the feature state of every feature of the source [sourceId], in
  /// the layer [sourceLayer] of a vector source.
  ///
  /// Fails with an [ArgumentError] if [sourceLayer] is null for a vector
  /// source or set for another source, and does nothing for a missing source,
  /// like [setFeatureState].
  void clearFeatureState(String sourceId, {String? sourceLayer}) {
    if (_detachedOrWarn()) return;
    final layer = _featureStateLayer(sourceId, sourceLayer);
    if (layer == null) return;
    _featureStates[sourceId]?.remove(layer);
    _backend.removeFeatureState(sourceId, sourceLayer: sourceLayer);
  }

  /// The key of [sourceLayer] in [_featureStates], after checking that the
  /// source [sourceId] has feature state in it, or null if the style has no
  /// such source. Debug builds warn about that once per source if [warn].
  String? _featureStateLayer(
    String sourceId,
    String? sourceLayer, {
    bool warn = true,
  }) {
    final source = _sources[sourceId];
    switch (source) {
      case null:
        if (warn && _warnedMissing.add(sourceId) && kDebugMode) {
          debugPrint(
            'maplibre: the style has no source "$sourceId", so its feature '
            'state did not change.',
          );
        }
        return null;
      case VectorSource() when sourceLayer == null:
        throw ArgumentError.value(
          sourceLayer,
          'sourceLayer',
          'A vector source needs the source layer of the feature',
        );
      case VectorSource():
        return sourceLayer!;
      case GeoJsonSource() when sourceLayer != null:
        throw ArgumentError.value(
          sourceLayer,
          'sourceLayer',
          'A GeoJSON source has no source layers',
        );
      case GeoJsonSource():
        return '';
      default:
        throw ArgumentError.value(
          sourceId,
          'sourceId',
          'Only GeoJSON and vector sources have feature state',
        );
    }
  }

  /// Fills the collection with the sources of a loaded style, by the `sources`
  /// member of its JSON. Platforms call it.
  void load(Map<String, Object?> sources) {
    for (final MapEntry(:key, :value) in sources.entries) {
      if (value is! Map<String, Object?>) continue;
      final source = Source.fromJson(key, value);
      _sources[key] = source;
      if (_isTileSource(source)) _specifications[key] = value;
    }
  }

  /// Merges what the TileJSON of the source [id] said into its object.
  /// Returns whether that changed anything. Platforms call it when a source
  /// changed.
  bool applyTileJson(
    String id, {
    String? attribution,
    double? minZoom,
    double? maxZoom,
    List<double>? bounds,
  }) {
    if (!_specifications.containsKey(id)) return false;
    final current = _sources[id]!.toJson()!;
    final merged = {
      ...current,
      if (attribution != null && attribution.isNotEmpty)
        'attribution': attribution,
      'minzoom': ?minZoom,
      'maxzoom': ?maxZoom,
      'bounds': ?bounds,
    };
    if (jsonEquals(current, merged)) return false;
    _sources[id] = Source.fromJson(id, merged);
    _changes.value++;
    return true;
  }

  /// Detaches the collection, when a new style is set on the map. Platforms
  /// call it. The collection still reads the sources of the style on screen,
  /// but takes no change, since the map's commands reach the new style.
  ///
  /// With [clearFeatureState], it first removes the feature state it set
  /// from the map: for a platform whose new style keeps the sources that
  /// didn't change, and with them their feature state.
  void markReplaced({bool clearFeatureState = false}) {
    if (_replaced) return;
    if (clearFeatureState) {
      _featureStates.keys.toList().forEach(_clearMapFeatureState);
    }
    _replaced = true;
  }

  /// Forgets every source, when the style goes away. Platforms call it after
  /// [markReplaced]. It empties the collection but does not stop
  /// changes by itself, so a caller that only disposes leaves writes going to
  /// an empty collection.
  void dispose() {
    _sources.clear();
    _specifications.clear();
    _featureStates.clear();
    _changes.value++;
  }

  /// Whether the map's source commands no longer reach the style of this
  /// collection. A change to it would reach the style that replaced it, which
  /// is likely a mistake, so debug builds warn once.
  bool _detachedOrWarn() {
    if (_replaced && !_warnedReplaced) {
      _warnedReplaced = true;
      if (kDebugMode) {
        debugPrint(
          'maplibre: the style was replaced, so changing its sources no '
          'longer updates the map.',
        );
      }
    }
    return _replaced;
  }

  T _sourceOfType<T extends Source>(String id) {
    final source = _sources[id];
    if (source is T) return source;
    throw ArgumentError.value(
      id,
      'id',
      source == null ? 'The style has no such source' : 'Not a $T',
    );
  }

  static String? _sourceIdOf(StyleLayer layer) => switch (layer) {
    StyleLayerWithSource(:final sourceId) => sourceId,
    UnknownStyleLayer(:final sourceId) => sourceId,
    _ => null,
  };

  static bool _isTileSource(Source source) =>
      source is RasterSource ||
      source is RasterDemSource ||
      source is VectorSource;

  Map<String, Object?> _tileSpecification(String id) {
    final source = _sources[id];
    if (source == null || !_isTileSource(source)) {
      throw ArgumentError.value(
        id,
        'id',
        source == null ? 'The style has no such source' : 'Not a tile source',
      );
    }
    return _specifications[id]!;
  }

  void _replaceTileSource(String id, Map<String, Object?> specification) {
    _sources[id] = Source.fromJson(id, specification);
    _specifications[id] = specification;
    // Not on web, the map adds the source again without its feature state,
    // so it goes on every platform.
    _clearMapFeatureState(id);
  }

  /// Removes the feature state of the source [id] from the map and the cache,
  /// per source layer, as gl-js needs the layer of a vector source.
  void _clearMapFeatureState(String id) {
    final layers = _featureStates.remove(id);
    if (layers == null) return;
    for (final layer in layers.keys) {
      _backend.removeFeatureState(
        id,
        sourceLayer: layer.isEmpty ? null : layer,
      );
    }
  }
}

/// Makes [owner] the owner of some sources of [sources], or no one if it is
/// null, see [setStyleOwner].
///
/// Not part of the public API: `style.dart` hides it.
void setStyleSourcesOwner(StyleSources sources, StyleOwner? owner) {
  sources._styleOwner = owner;
}
