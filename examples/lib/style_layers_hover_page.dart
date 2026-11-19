import 'package:http/http.dart';
import 'package:maplibre/maplibre.dart';
import 'package:material_ui/material_ui.dart';

@immutable
class StyleLayersHoverPage extends StatefulWidget {
  const StyleLayersHoverPage({super.key});

  static const location = '/style-layers/hover';

  @override
  State<StyleLayersHoverPage> createState() => _StyleLayersHoverPageState();
}

class _StyleLayersHoverPageState extends State<StyleLayersHoverPage> {
  static const _url =
      'https://maplibre.org/maplibre-gl-js/docs/assets/us_states.geojson';
  static const _sourceId = 'states';
  static const _color = Color(0xFF627BC1);

  /// The US states, each with an id, which feature state needs.
  late final Future<List<Feature>> _states = _loadStates();

  /// The selected state, whose name the page shows.
  RenderedFeature? _selected;
  Object? _error;

  static Future<List<Feature>> _loadStates() async {
    final response = await get(Uri.parse(_url));
    if (response.statusCode != 200) {
      throw Exception('Loading the states failed: ${response.statusCode}');
    }
    final states = FeatureCollection.parse(response.body).features;
    return [
      for (final (index, state) in states.indexed)
        Feature(
          id: index,
          geometry: state.geometry,
          properties: {'name': state.properties['STATE_NAME']},
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected?.properties['name'];
    return Scaffold(
      appBar: AppBar(title: const Text('Hover and Select')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _error?.toString() ??
                  (selected == null
                      ? 'Hover over a state with the mouse, or tap one.'
                      : 'Selected $selected.'),
            ),
          ),
          Expanded(
            child: MapLibreMap(
              options: const MapOptions(
                initCamera: CameraUpdate.position(
                  zoom: 2,
                  center: Geographic(lon: -100.486052, lat: 37.830348),
                ),
              ),
              onStyleLoaded: _onStyleLoaded,
              children: const [SourceAttribution(), MapControlButtons()],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    final List<Feature> states;
    try {
      states = await _states;
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
      return;
    }
    await style.sources.add(
      GeoJsonSource.data(
        id: _sourceId,
        data: .featureCollection(FeatureCollection(states)),
      ),
    );
    // Feature state changes how a state is drawn without touching the data
    // of the source, and without rebuilding a widget.
    final highlighted = Expression.any([
      Expression.equal(.featureState('hover'), const .literal(true)),
      Expression.equal(.featureState('selected'), const .literal(true)),
    ]);
    await style.layers.add(
      FillStyleLayer(
        id: 'state-fills',
        sourceId: _sourceId,
        color: const .literal(_color),
        opacity: .select([
          (highlighted, const .literal(1)),
        ], fallback: const .literal(0.5)),
        onEnter: (event) =>
            style.sources.setFeatureState(.of(event.feature), {'hover': true}),
        onLeave: (event) =>
            style.sources.removeFeatureState(.of(event.feature), key: 'hover'),
        onClick: (event) {
          if (_selected case final previous?) {
            style.sources.removeFeatureState(.of(previous), key: 'selected');
          }
          style.sources.setFeatureState(.of(event.feature), {'selected': true});
          setState(() => _selected = event.feature);
        },
      ),
    );
    await style.layers.add(
      LineStyleLayer(
        id: 'state-borders',
        sourceId: _sourceId,
        color: const .literal(_color),
        width: .select([
          (highlighted, const .literal(2)),
        ], fallback: const .literal(1)),
      ),
    );
  }
}
