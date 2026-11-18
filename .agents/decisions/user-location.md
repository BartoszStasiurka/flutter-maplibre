# User location

- **User location is a `MapPlugin`, `UserLocationLayer`, fed by a
  `Stream<UserLocation>`; there is no `PermissionManager`.** Tracking runs in
  Dart over `animateCamera`, and the plugin's `onCameraMoveStart` stops it
  when a gesture moves the map. Permissions are left to `geolocator` or `permission_handler`;
  `maplibre_geolocator` adapts `geolocator` positions.
- **The user location is drawn with style layers, styled by a
  `UserLocationStyle` (user decision on #689: one `style` object in the
  Flutter convention, no choice of renderer).** Style layers draw in the
  map's own frame, where a widget trails gl-js camera animations on web
  (every tracking `fly`) and can be a frame off on Android; the accuracy
  circle (`circle-pitch-alignment/scale: map`) and the heading
  (`icon-pitch-alignment: map`) also lie flat on a tilted map. The Android
  SDK's default `LocationComponent` renderer uses a GeoJSON source and style
  layers too. The layers are `MapPlugin.layers`, so they stay on every style;
  each is a private type of its own, so that the generated ids match them
  again on every fix, and the plugin gets the same instances while nothing
  changed. The layer doesn't depend on `CameraPosition.of`, so it doesn't
  rebuild while the camera moves. Each fix writes the one-feature sources
  once; nothing changes per frame, so the dot jumps from fix to fix as in
  gl-js. The accuracy radius is an exponential zoom interpolation of meters
  over 512 px tiles at the fix's latitude. The heading cone is a PNG drawn
  once per color at pixel ratio 3 and scaled by `radius / 8`.
