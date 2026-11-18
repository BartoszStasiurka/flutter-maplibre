# Offline

- **Every native map and the `OfflineManager` use one database,
  `maplibre_native.db` in the app support directory (`path_provider`).**
  Each map and the offline manager have a runtime of their own, and runtimes
  with the same `cache_path` share one database file source in the C
  library, so maps cache resources on disk and show downloaded regions.
  Without a cache path the C library keeps an in-memory database per
  runtime. On Android the offline manager initializes the C library through
  `MaplibreNativeApi.initialize`, as it creates no render target.
- **Offline downloads report their progress through the offline manager's
  runtime events.** A download observes its region and sets it active; the
  stream reports `offlineRegionStatusChanged` as progress, response errors
  as `OfflineResourceException`s, which the download retries, and an
  exceeded tile count limit as an `OfflineTileCountLimitException`.
  Cancelling the subscription sets the region inactive, and
  `resumeDownload` continues it. Metadata is UTF-8 JSON (#581).
- **Offline regions mirror the C API's definitions.**
  `OfflineRegionDefinition` is sealed, with a tile pyramid (bounds) and a
  geometry (a geobase `Geometry`, passed to the C API as decoded GeoJSON)
  variant, and `OfflineRegionStatus` carries every field of the C API's
  status. Geometry definitions compare by coordinates, since geobase
  geometries compare their coordinate lists by identity. MapLibre stores a
  tile that is not found (404) as empty, so only other failures reach the
  stream as errors.
