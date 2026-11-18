# Gestures

- **Two options decide what gestures do: `MapOptions.movements`
  (`MapMovements`: `pan`, `zoom`, `rotate`, `pitch`) and
  `MapOptions.gestures` (`MapGestures`: `drag`, `pinch`, `scrollWheel`,
  ...), all on by default.** A gesture moves the camera only along the
  movements that are on. Grouping gestures by movement didn't fit, because a
  two-finger pinch pans, zooms and rotates, and a right-button drag rotates
  and tilts; the user wanted the two kinds of switch in separate options.
  Min/max options can't replace the movement switches: there is no bearing
  limit, and limits also clamp the camera that the app sets. The
  model is the one of maplibre-compose, whose `MapInteractions` allows the
  `pan`, `zoom`, `rotate` and `pitch` movements and whose
  `InteractionBindings` bind inputs that can't enable a disallowed
  movement. The input names are Flutter's (`pinch`, `scrollWheel`,
  `doubleTapDrag`, `fling`) rather than Compose's (`transform`, `scroll`,
  `tapDrag`, momentum), and `secondaryDrag` matches `onSecondaryClick`. The
  C API has no gesture switches, only `mln_map_apply_camera_delta`. A
  new gesture, or an option such as cooperative gestures for maps in a
  scrolling list, is a new optional field, not a breaking change. A switch
  exists only for a gesture `MapGestureDetector` recognizes: there are no
  keyboard or box zoom switches until those are implemented.
- **Drags are map events, and annotation layers build feature dragging on
  them (#544, #151).** `MapGestureDetector` reports `onDragStart` (where the
  pointer went down), `onDrag` and `onDragEnd` for one-finger and
  primary-mouse drags, also while panning is off. As with double taps,
  `MapEventDragStart.preventDefault()` keeps the drag from panning, and an
  async `onDragStart` holds the pan until it completes; a pan that was not
  prevented then catches up, so the map stays under the finger. A second
  finger ends the drag; a prevented drag's pinch doesn't move the camera
  until every pointer is up.
- **Annotation layers drag their features themselves with `draggable: true`
  (#151), and the app saves the drop in `onDragEnd`.** The user chose this
  over #151's first plan, where the app moved the feature with `setState` on
  every `onDrag`: that rebuilt the page and re-sent the whole layer's
  source per step, 36 ms with 1,000 and 140 ms with 10,000 points on Linux
  against about 30 ms with one, and it beat a map-level list of draggable
  layers, which loses the feature's index in its layer's list. On a drag
  start `MapLibreMapState` queries the draggable layers in a 24 px square,
  prefers the nearest point and prevents the pan. `AnnotationManager.startDrag`
  then copies the feature into a one-feature overlay source and layer
  (`maplibre-drag-*`, the layer's own style) above its layer and hides it
  there with a filter on its `maplibre:index` property, which every feature
  of a draggable layer's source gets; app ids stay untouched. Each step
  writes only the overlay, coalesced to the latest geometry while a write
  is in flight, so a step costs about 20 ms at any layer size (the frame).
  Geometries move by the pointer's screen delta per vertex (Point,
  LineString, Polygon). The layer stays controlled: after the drop, the
  overlay stays until the app's list has the new place and its source has
  re-tiled (250 ms after the write, so the old place doesn't flash), or goes
  away after the next frame if the app didn't save it, and the feature snaps
  back. `LayerFeatureEvent` is not generic, because `Layer<Feature<Point>>`
  sits in a `List<Layer>`, where reading a callback field typed by `G` fails
  its covariance check. Callbacks are left out of `Layer.==`; the
  constructor asserts that they come with `draggable`.
- **Annotation layers report taps and hovers on their features with
  `onClick`, `onEnter` and `onLeave` (#647), on the same
  `LayerFeatureEvent` as drags.** #645 named it `LayerDragEvent`; it was
  renamed before a release, so that one event serves every layer callback.
  A layer with any of these callbacks or `draggable` is `interactive`, which
  is part of `Layer.==` and gives its source the `maplibre:index` property.
  A tap queries the clickable layers at the point, and in the 24 px grab
  square if that finds nothing; the topmost layer and its nearest point win.
  Hover, drag and click state is keyed by the manager's entry of a layer,
  not its index, so a reordered list neither repeats `onEnter` nor sends
  events to the wrong layer. `LayerFeatureEvent.feature` is the list's
  feature at `index`.
  Hover comes from new map events, `onPointerMove` (Flutter hover events:
  mice and styluses without a pressed button) and `onPointerLeave` (a
  `MouseRegion` that always wraps the detector, so that the child keeps its
  state). Each move queries the hovered layers at the point, coalesced to
  the latest move while a query runs, and enter/leave are tracked per layer
  like gl-js `mouseenter`/`mouseleave`, but per feature.
- **Style layers report taps and hovers with `onClick`, `onEnter` and
  `onLeave` on the `StyleLayer` object (#647), not with a declarative list
  on `MapLibreMap`.** Annotations are the declarative API and style layers
  the imperative one, so the callbacks are fields like the property setters,
  and constructor parameters of the types with vector features (from the
  generator). They end with the object: the map only calls a layer that is
  still `style.layers[id]`. The event is `StyleLayerFeatureEvent` with the
  `RenderedFeature`. Unlike annotation layers, every style layer under a tap
  reports it, as with gl-js `map.on('click', layerId)`. Enter/leave is per
  feature id, or per layer for features without one. The same query serves
  annotation and style layers. A callback set on a style layer doesn't
  rebuild the map, so `StyleLayers.callbacksChanged` notifies when a layer
  gets its first callback or loses its last one (setter, add, remove,
  dispose), and the map rebuilds to wire the detector's `onClick`,
  `onPointerMove` and `onPointerLeave` only while something needs them. One
  frame late is fine: no tap or move can come in between. The repaint
  triggers of the platforms don't help, they render a map frame and don't
  rebuild widgets.
- **One gesture recognizer in Dart serves every platform:
  `MapGestureDetector` in `maplibre_platform_interface`.** It sits there, not
  in `maplibre`, because the platform packages need it and `maplibre` depends
  on them. `MapLibreMapState.build` wraps the platform widget in it when the
  state returns a `gestureCamera`. Flutter hit-tests every pointer, so
  widgets over the map keep theirs.
- **The recognizer hands the platforms screen-space intents through
  `GestureCameraSink`, never map centers.** A step (`GestureCameraUpdate`)
  pans the content under one screen point to another, then zooms, rotates
  and tilts around a screen point. Each platform applies it with its own
  projection-aware camera engine, so a new projection (globe) needs no Dart
  change. `gestureEnd` carries a `GestureVelocity`: the pan's release
  velocity (of the focal point for more than one pointer, as Flutter reports
  only the last pointer's), and a pinch's zoom and rotation velocities from
  a `VelocityTracker` over the steps it applied; fling inertia runs in the
  platform. Discrete zooms (wheel, double tap) use `zoomBy`.
- **Native applies steps with `mln_map_apply_camera_delta`**, the C API's
  equivalent of mbgl's moveBy/scaleBy/rotateBy/pitchBy, one atomic delta per
  step with the gesture phase. A released gesture flings as the map's
  gesture momentum (`mln_gesture_momentum` on the end delta, with the core's
  default friction decay for pan, zoom and bearing), which the next
  gesture's begin stops. Native and web feel different on purpose: native
  uses the core's fling. The move ends from the end delta's transition end
  handler, which also runs at once for a release too slow to fling.
- **On web, Flutter is the only hit-tester.** The gl-js map is created with
  `interactive: false` and its container has `pointer-events: none`, so the
  browser hands every pointer to Flutter, and widgets over the map no longer
  leak taps and drags to gl-js. Clicks, double, secondary and long clicks
  come from `MapGestureDetector`. The `HtmlElementView` hit-tests as
  transparent: an opaque platform view joins the gesture arena first and
  wins every pointer the arena sweeps, so single and secondary taps (in real
  browsers too) never reached the tap recognizer. A right click or Ctrl +
  click that starts on the map suppresses the browser's context menu once.
- **Widgets over the map need no `PointerInterceptor`, so `maplibre` and
  `maplibre_web` dropped the package.** It only put an invisible HTML element
  under its child, so the browser would not route the pointer to the map's
  element; the map's element takes no pointers anymore. Non-interactive
  `WidgetLayer` markers still use `TranslucentPointer`, so drags that start
  on them pan the map on every platform.
- **Web applies steps with public gl-js camera calls of duration 0.** A pan
  puts `unproject(panFrom)` at `panTo` through `easeTo`'s `center` +
  `offset`, so the grabbed location stays under the pointer in every
  projection. gl-js's `around` drifts by up to 325 px on the globe (zoom 3,
  cursor in a corner), so zoom, rotation and pitch around a point don't use
  it: the web sink changes the camera, puts the location back with the pan
  step, reads the result and restores the camera, all without reporting
  events, and then applies the result in one `jumpTo`, or one animated
  `easeTo` for a double tap. Wheel, pinch and double-tap zoom then keep the
  location under the cursor within 0.01 px on the globe and on Mercator.
  One gesture reports one camera move, although gl-js fires
  movestart/moveend per step.
  A release flings with gl-js's own inertia constants (linearity 0.3,
  ease-out bezier; max speed and deceleration 1400 px/s and 2500 px/s² for
  pan, 40 and 20 levels for zoom, 360° and 1000° for bearing) in one
  `easeTo`, whose zoom and bearing target comes from the same exact-around
  step.
- **Globe on web needs no forwarding to gl-js handlers.** Measured with
  gl-js 5.24 at 1024×768: the grabbed point stays within 0.1 px at zoom 2 and
  above, also at 80° N and pitched 45°. At zoom 1 a drag from the center to
  near the globe's edge ends 8.6 px off, and one that starts near the pole
  98 px off. gl-js's own globe drag drifts as much or more (3–86 px over the
  same drags), so the fallback of forwarding pointer events to its handlers
  would not be better.
- **Double taps are only recognized while `onDoubleClick` is set or the
  zoom gesture is on.** A double tap recognizer holds every single tap
  until the double tap timeout, so `onClick` fires at once without one.
- **`MapEventDoubleClick.preventDefault()` stops the double tap zoom**, as
  in gl-js, rather than a `bool` return: a `bool?` callback rejects
  `(e) => setState(...)` and warns on block bodies without a return.
  `onDoubleClick` returns `FutureOr<void>` so it can query features first.
  It fires on the second press and the zoom runs on release, so the detector
  waits for the Future then; the double tap and drag zoom waits too and is
  prevented as well.
- **The gestures follow the platform conventions.** A two-finger twist turns
  the map with the fingers (negated bearing). Double tap and drag zooms
  (down zooms in, 150 px per level). Two fingers side by side dragged
  vertically tilt, as on MapLibre Android. A right-button or Ctrl +
  left-button drag rotates and tilts as in MapLibre GL JS: 0.8° bearing per
  horizontal pixel, flipped above the center so the map turns like a wheel,
  and 0.5° pitch per vertical pixel, up tilting further. A scroll wheel zooms
  1/450 level per CSS pixel, as GL JS (Flutter web divides the browser's
  wheel delta by the device pixel ratio except on macOS, so the recognizer
  multiplies it back); a trackpad pinch that arrives as a scale signal
  zooms by its scale.
- **A pinch rotates only after its fingers twist
  `MapGestures.rotateThreshold` degrees (default 15) since it started.** The
  twist below it is dropped, so the map doesn't jump; zoom and pan are never
  held back. GL JS waits for 25 px along the circle of the fingers (about 14°
  at 200 px apart); MapLibre Android waits 3° to 15° depending on speed and
  turns rotation off once a zoom starts first; iOS waits 3° while zooming;
  flutter_map waits 20° only with `enableMultiFingerGestureRace`, where the
  first gesture past its threshold locks the others out. A fixed angle is
  easier to explain and set than GL JS's distance, and locking rotation out
  after a zoom would make zooming and turning at once impossible.
- **A long click is a hold of one finger.** Flutter's long press recognizer
  times the first pointer alone and wins the arena when its deadline passes,
  whatever else landed, so two fingers resting on the map before a pinch were
  a long click and the pinch never moved the camera. The map's recognizer
  rejects itself when a second finger lands before the deadline, and stays
  out until every finger has lifted; a hold past its deadline stays. The
  deadline, not the arena, decides, since the arena can go to the long press
  early when it is alone there. The detector gives its semantics the long
  press action itself, as the default semantics only find Flutter's own
  recognizer.
