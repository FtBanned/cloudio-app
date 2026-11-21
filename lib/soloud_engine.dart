import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_soloud/flutter_soloud.dart';

String? _lastAudioLog;

/// Audio xətalarını loga yazır. Eyni xəta ardıcıl təkrarlananda (məs. _tick saniyədə 5 dəfə
/// işləyir) log doldurmasın deyə təkrar mesajlar buraxılır.
void audioLog(String where, Object error) {
  final msg = '[Cloudio] $where: $error';
  if (msg == _lastAudioLog) return;
  _lastAudioLog = msg;
  debugPrint(msg);
}

/// SoLoud ses mühərrikinin tək nöqtəli idarəsi: başlatma + qlobal effekt zənciri.
///
/// Zəncir (sıra vacibdir): [pitch düzəldici] -> EQ -> kompressor (+makeup) -> limiter.
/// Limiter ən sonda durur ki, 10x gücləndirmədə belə çıxış tavanı aşılmasın.
class SoloudEngine {
  SoloudEngine._();
  static final SoloudEngine instance = SoloudEngine._();

  static const int kBands = 10;

  bool ready = false;

  Future<void> init() async {
    if (ready) return;
    try {
      await SoLoud.instance.init();
      ready = true;
      // Çıxış cihazı avtomatik başlamasa (məs. iOS-da qulaqlıq dəyişəndən sonra),
      // səssiz qalmasın deyə cihazı yenidən başlatmağa cəhd edirik.
      await _failSub?.cancel();
      _failSub = SoLoud.instance.audioDeviceStartFailures.listen((e) {
        audioLog('səs cihazı avtomatik başlamadı', e);
        unawaited(restartDevice());
      });
    } catch (e) {
      debugPrint('[Cloudio] SoLoud başlamadı: $e');
    }
  }

  StreamSubscription<dynamic>? _failSub;
  bool _restarting = false;

  /// Çıxış cihazını dayandırıb yenidən başladır. Yüklənmiş mahnılar, cari pozisiya və
  /// filtrlər qalır. Qulaqlıq çıxıb-taxılandan sonra iOS-da cihaz səssiz qala bilir.
  Future<void> restartDevice() async {
    if (!ready || kIsWeb || _restarting) return;
    _restarting = true;
    try {
      try {
        await SoLoud.instance.stopAudioDevice();
      } catch (e) {
        audioLog('stopAudioDevice', e);
      }
      try {
        await SoLoud.instance.startAudioDevice();
      } catch (e) {
        audioLog('startAudioDevice', e);
      }
    } finally {
      _restarting = false;
    }
  }

  // ---- istənilən vəziyyət ----
  bool _wantFx = false;
  double _speed = 1.0;
  List<double> _bands = List<double>.filled(kBands, 1.0);
  double _makeupDb = 0;
  double _ratio = 1;
  double _threshold = -12;
  double _limThreshold = -3;
  double _limCeiling = -1;

  // ---- hazırda aktiv olan ----
  bool _fxActive = false;
  bool _pitchActive = false;

  bool get _wantPitch => (_speed - 1.0).abs() > 0.001;

  /// Oxuma sürəti dəyişəndə SoLoud tonu da dəyişir; bunu əks pitch-shift ilə düzəldirik
  /// (just_audio-dakı kimi ton sabit qalsın).
  void setSpeed(double speed) {
    _speed = speed;
    _sync();
  }

  /// Gücləndirici zəncirinin parametrləri. [fx] false isə EQ/kompressor/limiter söndürülür.
  void configure({
    required bool fx,
    required List<double> bands,
    required double makeupDb,
    required double ratio,
    required double threshold,
    required double limThreshold,
    required double limCeiling,
  }) {
    _wantFx = fx;
    _bands = List<double>.of(bands);
    _makeupDb = makeupDb;
    _ratio = ratio;
    _threshold = threshold;
    _limThreshold = limThreshold;
    _limCeiling = limCeiling;
    _sync();
  }

  /// Yalnız gücləndirmə (dB): yumşaq qalxma zamanı tez-tez çağırılır.
  void setMakeup(double db) {
    _makeupDb = db;
    if (!ready || !_fxActive) return;
    try {
      SoLoud.instance.filters.compressorFilter.makeupGain.value = db;
    } catch (e) {
      audioLog('setMakeup', e);
    }
  }

  void _sync() {
    if (!ready) return;
    if (_wantFx != _fxActive || _wantPitch != _pitchActive) _rebuildChain();
    _pushParams();
  }

  void _rebuildChain() {
    final f = SoLoud.instance.filters;
    try {
      if (f.limiterFilter.isActive) f.limiterFilter.deactivate();
      if (f.compressorFilter.isActive) f.compressorFilter.deactivate();
      if (f.parametricEqFilter.isActive) f.parametricEqFilter.deactivate();
      if (f.pitchShiftFilter.isActive) f.pitchShiftFilter.deactivate();
      if (_wantPitch) f.pitchShiftFilter.activate();
      if (_wantFx) {
        final eq = f.parametricEqFilter;
        eq.activate();
        eq.numBands.value = kBands.toDouble();
        eq.stftWindowSize.value = 1024;
        f.compressorFilter.activate();
        f.limiterFilter.activate();
      }
    } catch (e) {
      debugPrint('[Cloudio] filtr zənciri qurulmadı: $e');
    }
    _fxActive = _wantFx;
    _pitchActive = _wantPitch;
  }

  void _pushParams() {
    final f = SoLoud.instance.filters;
    if (_pitchActive) {
      try {
        f.pitchShiftFilter.shift.value = (1.0 / _speed).clamp(0.5, 2.0).toDouble();
      } catch (e) {
        debugPrint('[Cloudio] pitch düzəldici: $e');
      }
    }
    if (!_fxActive) return;
    try {
      final eq = f.parametricEqFilter;
      for (var i = 0; i < kBands; i++) {
        eq.bandGain(i).value = _bands[i];
      }
      final comp = f.compressorFilter;
      comp.makeupGain.value = _makeupDb;
      comp.ratio.value = _ratio;
      comp.threshold.value = _threshold;
      comp.attackTime.value = 5;
      comp.releaseTime.value = 120;
    } catch (e) {
      debugPrint('[Cloudio] EQ/kompressor: $e');
    }
    // Limiter ayrıca: bu sahələr köhnə versiyada yoxdursa yuxarıdakılar yenə işləsin
    try {
      final lim = f.limiterFilter;
      lim.threshold.value = _limThreshold;
      lim.outputCeiling.value = _limCeiling;
    } catch (e) {
      debugPrint('[Cloudio] limiter parametrləri: $e');
    }
  }
}