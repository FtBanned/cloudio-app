import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Qulaqlıq (naqilli / Bluetooth / AirPods) çıxarılanda və ya taxılanda xəbər verir.
/// iOS və Android üçün (audio_session üzərindən).
class AudioRouteWatcher {
  AudioRouteWatcher({required this.onRemoved, required this.onAdded});

  /// Qulaqlıq çıxdı / ayrıldı.
  final void Function() onRemoved;

  /// Qulaqlıq taxıldı / qoşuldu.
  final void Function() onAdded;

  final List<StreamSubscription<dynamic>> _subs = [];

  /// Daxili dinamik / qulaq hissəsi qulaqlıq sayılmır.
  static bool _isExternalOutput(AudioDevice d) {
    if (!d.isOutput) return false;
    switch (d.type) {
      case AudioDeviceType.builtInSpeaker:
      case AudioDeviceType.builtInSpeakerSafe:
      case AudioDeviceType.builtInEarpiece:
      case AudioDeviceType.unknown:
        return false;
      default:
        return true;
    }
  }

  Future<void> start() async {
    try {
      final session = await AudioSession.instance;
      _subs.add(session.becomingNoisyEventStream.listen((_) => onRemoved()));
      _subs.add(session.devicesChangedEventStream.listen((e) {
        if (e.devicesRemoved.any(_isExternalOutput)) onRemoved();
        if (e.devicesAdded.any(_isExternalOutput)) onAdded();
      }));
    } catch (e) {
      debugPrint('[Cloudio] Qulaqlıq izləmə başlamadı: $e');
    }
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}
