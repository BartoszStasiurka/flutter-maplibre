# Linux

- **Frames reach Flutter as an `FlTextureGL` that samples the ring slots
  directly. MapLibre renders through Vulkan into a ring of RGBA8 images with
  exportable memory, which the plugin allocates on the library's device; `populate` imports each slot's opaque file descriptor
  once (`GL_EXT_memory_object_fd`) and returns the latest presented slot's
  texture.** Flutter 3.47 renders in EGL contexts of its own
  (`FlOpenGLManager`) that share nothing with any context a plugin can
  create, and `populate` is the only code that runs with one current, so
  every OpenGL call of the texture runs there. Opaque memory needs one GPU
  and driver on both sides: the library creates its Vulkan device on the
  OpenGL device UUID, the plugin checks the device and driver UUIDs, and checks the extensions,
  OpenGL ES 3.0 and the UUIDs again in Flutter's context on the first
  `populate`. If that fails, it logs a warning and the map shows nothing;
  otherwise failures fall back to an `FlPixelBufferTexture`, as on Windows.
- **A slot is in use while it is the front or shown slot, or until a fence
  says Flutter's draws that sampled it are done.** Flutter takes no fence for
  an external texture and samples the texture of the last `populate` until
  it populates again. So when `populate` moves Flutter to a new slot, it
  inserts a `glFenceSync` for the slot Flutter leaves, polls it, and waits
  for older fences, which are a frame old, so that at most one slot
  waits for its fence and a ring of three always has one to render into.
  `maplibre_native_gpu_texture_slot_in_use` reports this to Dart.
- **OpenGL objects are deleted in a later `populate`.** A resize moves the old
  ring's textures, memory objects and fences to a list that the texture's next
  `populate` deletes; a disposed texture hands them to a plugin-wide list that
  any texture's `populate` deletes. The objects of the last map stay until the
  process ends. Vulkan frees its side right away; the OpenGL memory objects
  keep the allocations alive.
- **The GPU IDs are read from an EGL context like Flutter's, once, when
  Dart first calls the plugin on the GTK main thread.** The plugin creates
  an OpenGL ES 2 context on the window's display (X11 or Wayland, as
  `FlOpenGLManager` does) and makes it current surfaceless on a short-lived
  thread of its own, since Mesa refuses it on the main thread where Flutter's
  contexts live. It checks OpenGL ES 3.0, `GL_EXT_memory_object_fd` and the
  UUIDs there, so a GPU whose OpenGL ES cannot import Vulkan memory falls
  back to CPU readback before a map is shown; the check in the first
  `populate` stays as a guard. The context is destroyed right after; the
  textures need no context of the plugin's own, so creating and presenting
  them works on any thread. If Dart's first call to the plugin is not on the
  main thread (unmerged threads), frames are read back to the CPU.
- **The plugin lives as long as the process.** Linux plugins get no
  shutdown call, and sessions on core workers can outlive the engine.
