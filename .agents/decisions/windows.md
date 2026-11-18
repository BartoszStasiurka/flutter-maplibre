# Windows

- **The session renders into the library's ring of three DXGI shared
  textures (`attachDxgiSharedTextureRing`), and the plugin copies each frame
  into one of three textures that Flutter shows as a DXGI GPU surface
  texture.** The plugin opens each ring texture once with
  `OpenSharedResource1` on its D3D11 device on Flutter's adapter. Flutter
  can't take the ring's textures directly: ANGLE opens only legacy shared
  handles, the library shares NT handles, and Flutter reopens a texture
  whenever the handle changes. The copy finishes before the frame is
  released, so the library never renders into a texture being copied. If
  sharing fails (no Vulkan device on the adapter's LUID, as with lavapipe in
  CI), frames are read back to the CPU into a pixel buffer texture.
- **No keyed mutex on the shared textures.** Flutter/ANGLE never acquire it.
  Tearing is unlikely but possible.
- **The C library is built with MSVC 14.37.** 14.44 needs LLVM 19 or newer.
