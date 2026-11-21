import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

import 'soloud_engine.dart';

/// just_audio-nun AudioPlayer-i ilə eyni səthi (PlayerController-in istifadə etdiyi hissə)
/// SoLoud üzərində verir. Beləliklə mühərriki dəyişmək üçün PlayerController-də
/// yalnız pleyerin tipi dəyişir; gücləndirici filtrlər isə SoLoud-un qlobal zəncirindədir.
class SoloudPlayer {
  SoloudPlayer() {
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  AudioSource? _src;
  SoundHandle? _h;
  bool _playing = false;
  ProcessingState _ps = ProcessingState.idle;
  Duration? _dur;
  Duration _lastPos = Duration.zero;
  double _vol = 1.0;
  double _speed = 1.0;
  int _loadSeq = 0;
  bool _disposed = false;
  Timer? _timer;

  final _stateCtl = StreamController<void>.broadcast();
  final _psCtl = StreamController<ProcessingState>.broadcast();
  final _posCtl = StreamController<Duration>.broadcast();
  final _durCtl = StreamController<Duration?>.broadcast();

  // ---- just_audio ilə eyni adlı axınlar (qoşulanda cari dəyəri dərhal verir) ----
  Stream<void> get playerStateStream async* {
    yield null;
    yield* _stateCtl.stream;
  }

  Stream<void> get playbackEventStream => _stateCtl.stream;

  Stream<ProcessingState> get processingStateStream async* {
    yield _ps;
    yield* _psCtl.stream;
  }

  Stream<Duration> get positionStream async* {
    yield position;
    yield* _posCtl.stream;
  }

  Stream<Duration?> get durationStream async* {
    yield _dur;
    yield* _durCtl.stream;
  }

  // ---- vəziyyət ----
  bool get playing => _playing;
  ProcessingState get processingState => _ps;
  Duration? get duration => _dur;
  double get speed => _speed;
  Duration get bufferedPosition => _dur ?? Duration.zero;

  Duration get position {
    final h = _h;
    if (h != null) {
      try {
        if (SoLoud.instance.getIsValidVoiceHandle(h)) {
          return SoLoud.instance.getPosition(h);
        }
      } catch (e) {
        audioLog('position oxunmadı', e);
      }
    }
    return _lastPos;
  }

  bool get _handleValid {
    final h = _h;
    if (h == null) return false;
    try {
      return SoLoud.instance.getIsValidVoiceHandle(h);
    } catch (e) {
      audioLog('getIsValidVoiceHandle', e);
      return false;
    }
  }

  void _setPs(ProcessingState s) {
    if (_ps == s) return;
    _ps = s;
    _psCtl.add(s);
    _stateCtl.add(null);
  }

  // ---- yükləmə ----
  /// Telefonda: fayl yolundan. Diskdən axın rejimi: bütün mahnını PCM-ə açıb RAM-ı doldurmur.
  Future<Duration?> setFilePath(String path, {Duration? initialPosition}) {
    final p = path.toLowerCase();
    final native = p.endsWith('.m4a') || p.endsWith('.aac') || p.endsWith('.mp4');
    return _load(() async {
      if (!native) return SoLoud.instance.loadFile(path, mode: LoadMode.disk);
      // m4a/aac (telefonun öz dekoderi): əvvəl disk rejimi; alınmazsa və ya
      // uzunluq 0 çıxarsa yaddaş rejimi ilə yenidən yoxlanır.
      try {
        final s = await SoLoud.instance.loadFile(path, mode: LoadMode.disk);
        if (SoLoud.instance.getLength(s) > Duration.zero) return s;
        try {
          await SoLoud.instance.disposeSource(s);
        } catch (e) {
          audioLog('m4a: ilkin mənbə dispose olunmadı', e);
        }
      } catch (e) {
        debugPrint('[Cloudio] m4a/aac disk rejimi alınmadı, yaddaş rejimi: $e');
      }
      return SoLoud.instance.loadFile(path, mode: LoadMode.memory);
    }, initialPosition);
  }

  /// Veb-də: fayl yolu yoxdur, baytlardan yaddaşa yüklənir.
  Future<Duration?> setBytes(Uint8List bytes, {required String name, Duration? initialPosition}) {
    return _load(
      () => SoLoud.instance.loadMem(name, bytes, mode: LoadMode.memory),
      initialPosition,
    );
  }

  Future<Duration?> _load(Future<AudioSource> Function() loader, Duration? initialPosition) async {
    final seq = ++_loadSeq;
    _setPs(ProcessingState.loading);
    await _release();
    final AudioSource src;
    try {
      src = await loader();
    } catch (e) {
      if (seq == _loadSeq) _setPs(ProcessingState.idle);
      rethrow;
    }
    if (seq != _loadSeq || _disposed) {
      try {
        await SoLoud.instance.disposeSource(src);
      } catch (e) {
        audioLog('yarımçıq yükləmənin mənbəyi dispose olunmadı', e);
      }
      throw Exception('Loading interrupted');
    }
    _src = src;
    _dur = SoLoud.instance.getLength(src);
    _durCtl.add(_dur);
    _lastPos = initialPosition ?? Duration.zero;
    final h = SoLoud.instance.play(src, volume: _vol, paused: true);
    _h = h;
    if ((_speed - 1.0).abs() > 0.001) {
      SoLoud.instance.setRelativePlaySpeed(h, _speed);
    }
    if (initialPosition != null && initialPosition > Duration.zero) {
      SoLoud.instance.seek(h, initialPosition);
    }
    _setPs(ProcessingState.ready);
    // just_audio kimi: "playing" bayrağı mahnı dəyişəndə qalır, yeni mahnı hazır olanda başlayır
    if (_playing) SoLoud.instance.setPause(h, false);
    _posCtl.add(_lastPos);
    return _dur;
  }

  Future<void> _release() async {
    final h = _h;
    final s = _src;
    _h = null;
    _src = null;
    _dur = null;
    if (h != null) {
      try {
        await SoLoud.instance.stop(h);
      } catch (e) {
        audioLog('stop (handle) xətası', e);
      }
    }
    if (s != null) {
      try {
        await SoLoud.instance.disposeSource(s);
      } catch (e) {
        audioLog('mənbə dispose olunmadı', e);
      }
    }
  }

  /// Mahnı bitibsə (handle ləğv olunub) yeni handle yaradır.
  void _ensureHandle({required bool paused}) {
    final src = _src;
    if (src == null || _handleValid) return;
    final h = SoLoud.instance.play(src, volume: _vol, paused: paused);
    _h = h;
    if ((_speed - 1.0).abs() > 0.001) {
      SoLoud.instance.setRelativePlaySpeed(h, _speed);
    }
  }

  // ---- idarəetmə ----
  Future<void> play() async {
    _playing = true;
    if (_src != null && _ps != ProcessingState.loading) {
      try {
        if (_handleValid) {
          SoLoud.instance.setPause(_h!, false);
        } else {
          _lastPos = Duration.zero;
          _ensureHandle(paused: false);
        }
        if (_ps == ProcessingState.completed) _setPs(ProcessingState.ready);
      } catch (e) {
        debugPrint('[Cloudio] play xətası: $e');
      }
    }
    _stateCtl.add(null);
  }

  Future<void> pause() async {
    _playing = false;
    try {
      if (_handleValid) SoLoud.instance.setPause(_h!, true);
    } catch (e) {
      debugPrint('[Cloudio] pause xətası: $e');
    }
    _stateCtl.add(null);
  }

  Future<void> stop() async {
    _loadSeq++; // gözləyən yükləmə ləğv olsun
    _playing = false;
    await _release();
    _lastPos = Duration.zero;
    _setPs(ProcessingState.idle);
    _stateCtl.add(null);
  }

  Future<void> seek(Duration? position) async {
    if (_src == null) return;
    var p = position ?? Duration.zero;
    final d = _dur;
    if (d != null && p > d) p = d;
    try {
      _ensureHandle(paused: !_playing);
      final h = _h;
      if (h != null) SoLoud.instance.seek(h, p);
      if (_ps == ProcessingState.completed) _setPs(ProcessingState.ready);
      _lastPos = p;
      _posCtl.add(p);
    } catch (e) {
      debugPrint('[Cloudio] seek xətası: $e');
    }
  }

  /// Hər mahnının öz səsi (0..1). 1-dən yuxarı gücləndirmə qlobal zəncirdədir (Booster).
  Future<void> setVolume(double v) async {
    _vol = v.clamp(0.0, 1.0).toDouble();
    try {
      if (_handleValid) SoLoud.instance.setVolume(_h!, _vol);
    } catch (e) {
      audioLog('setVolume', e);
    }
  }

  Future<void> setSpeed(double v) async {
    _speed = v;
    try {
      if (_handleValid) SoLoud.instance.setRelativePlaySpeed(_h!, v);
    } catch (e) {
      audioLog('setRelativePlaySpeed', e);
    }
    SoloudEngine.instance.setSpeed(v);
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await stop();
    await _stateCtl.close();
    await _psCtl.close();
    await _posCtl.close();
    await _durCtl.close();
  }

  // ---- saat: mövqe axını və mahnı sonu ----
  void _tick() {
    if (_disposed) return;
    final h = _h;
    if (h == null) return;
    try {
      if (!SoLoud.instance.getIsValidVoiceHandle(h)) {
        _h = null;
        if (_ps == ProcessingState.ready && _playing) {
          // just_audio kimi: bitəndə "playing" qalır, vəziyyət "completed" olur
          _lastPos = _dur ?? _lastPos;
          _posCtl.add(_lastPos);
          _setPs(ProcessingState.completed);
        }
        return;
      }
      if (_playing && _ps == ProcessingState.ready) {
        _lastPos = SoLoud.instance.getPosition(h);
        _posCtl.add(_lastPos);
      }
    } catch (e) {
      audioLog('_tick (mövqe/handle oxunmadı)', e);
    }
  }
}
