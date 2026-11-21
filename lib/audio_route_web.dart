import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

/// Web üçün sınaq versiyası: brauzerin "devicechange" hadisəsində səs çıxış
/// cihazlarının sayı azalırsa "çıxdı", artırsa "taxıldı" sayılır.
/// (Brauzer icazəsiz cihaz adlarını vermir, ona görə yalnız say müqayisə olunur.)
class AudioRouteWatcher {
  AudioRouteWatcher({required this.onRemoved, required this.onAdded});

  final void Function() onRemoved;
  final void Function() onAdded;

  int? _count;
  JSFunction? _listener;

  Future<int> _outputCount() async {
    final list = await web.window.navigator.mediaDevices.enumerateDevices().toDart;
    return list.toDart.where((d) => d.kind == 'audiooutput').length;
  }

  Future<void> _check() async {
    try {
      final n = await _outputCount();
      final old = _count;
      _count = n;
      if (old == null) return;
      if (n < old) onRemoved();
      if (n > old) onAdded();
    } catch (e) {
      debugPrint('[Cloudio] devicechange oxunmadı: $e');
    }
  }

  Future<void> start() async {
    try {
      _count = await _outputCount();
      final fn = ((web.Event _) {
        unawaited(_check());
      }).toJS;
      _listener = fn;
      web.window.navigator.mediaDevices.addEventListener('devicechange', fn);
    } catch (e) {
      debugPrint('[Cloudio] Qulaqlıq izləmə (web) başlamadı: $e');
    }
  }

  void dispose() {
    final fn = _listener;
    if (fn == null) return;
    try {
      web.window.navigator.mediaDevices.removeEventListener('devicechange', fn);
    } catch (_) {}
    _listener = null;
  }
}
