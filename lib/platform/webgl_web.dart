import 'package:web/web.dart' as web;

/// MapLibre GL JS needs WebGL. Some browsers (or hardware-acceleration off) lack it.
bool webglAvailable() {
  try {
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
    return canvas.getContext('webgl2') != null || canvas.getContext('webgl') != null;
  } catch (_) {
    return true;
  }
}
