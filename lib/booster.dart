import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'persistence.dart';
import 'soloud_engine.dart';

/// Səs gücləndirici: 1x ... 10x əmsal + aydınlıq (EQ) + yumşaq limiter.
/// Ayarlar saxlanılır; effekt zənciri SoloudEngine-dədir.
class Booster extends ChangeNotifier {
  Booster._();
  static final Booster instance = Booster._();

  static const List<double> kMults = [1, 2, 3, 5, 8, 10];
  static const int kBands = SoloudEngine.kBands;

  /// Bantlar loqarifmik: ~30 Hz ... 12 kHz. 1.0 = dəyişmir, 2.0 ≈ +6 dB (maks 4.0).
  static const Map<String, List<double>> kClarity = {
    'tebii': [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    'aydin': [0.7, 0.7, 0.8, 1.0, 1.3, 1.8, 2.2, 2.2, 1.8, 1.4],
    'kristal': [0.55, 0.6, 0.7, 0.8, 1.1, 1.9, 2.8, 3.0, 2.4, 1.8],
  };
  static const Map<String, String> kClarityNames = {
    'tebii': 'Doğal',
    'aydin': 'Berrak vokal',
    'kristal': 'Kristal',
  };

  bool enabled = false;
  double mult = 1;
  String clarity = 'aydin';
  double extraDb = 0;
  double ratio = 1;
  double threshold = -12;
  double limThreshold = -3;
  double limCeiling = -1;
  final List<double> bandGain = List<double>.of(kClarity['aydin']!);

  double _curDb = 0; // həqiqətən tətbiq olunan gücləndirmə (yumşaq qalxma)
  Timer? _ramp;

  /// 20*log10(mult) + əlavə. Kompressorun makeup tavanı +40 dB.
  double get targetDb =>
      (20 * math.log(mult) / math.ln10 + extraDb).clamp(0.0, 40.0).toDouble();

  bool get engineReady => SoloudEngine.instance.ready;

  String get label =>
      !enabled ? 'Kapalı' : '${mult.toStringAsFixed(mult == mult.roundToDouble() ? 0 : 1)}x';

  // ---- yükləmə / saxlama ----
  Future<void> load() async {
    final m = await CloudioStore.instance.loadBooster();
    if (m != null) {
      enabled = m['on'] as bool? ?? false;
      mult = ((m['mult'] as num?)?.toDouble() ?? 1).clamp(1.0, 10.0).toDouble();
      final c = m['clarity'] as String?;
      if (c != null && kClarity.containsKey(c)) clarity = c;
      extraDb = ((m['extra'] as num?)?.toDouble() ?? 0).clamp(0.0, 12.0).toDouble();
      ratio = ((m['ratio'] as num?)?.toDouble() ?? ratio).clamp(1.0, 8.0).toDouble();
      threshold = ((m['thr'] as num?)?.toDouble() ?? threshold).clamp(-60.0, 0.0).toDouble();
      limThreshold =
          ((m['limThr'] as num?)?.toDouble() ?? limThreshold).clamp(-24.0, 0.0).toDouble();
      limCeiling =
          ((m['limCeil'] as num?)?.toDouble() ?? limCeiling).clamp(-12.0, 0.0).toDouble();
      final b = m['bands'];
      if (b is List && b.length == kBands) {
        for (var i = 0; i < kBands; i++) {
          bandGain[i] = ((b[i] as num).toDouble()).clamp(0.0, 4.0).toDouble();
        }
      } else {
        _fillBands();
      }
    } else {
      _autoTune();
    }
    // Açılışda həmişə sakit başlayır: qalxma 0 dB-dən başlayır
    _curDb = 0;
    _startRamp();
    notifyListeners();
  }

  void _save() {
    unawaited(CloudioStore.instance.saveBooster(<String, Object?>{
      'on': enabled,
      'mult': mult,
      'clarity': clarity,
      'extra': extraDb,
      'ratio': ratio,
      'thr': threshold,
      'limThr': limThreshold,
      'limCeil': limCeiling,
      'bands': List<double>.of(bandGain),
    }));
  }

  // ---- dəyişdirmə ----
  void setEnabled(bool on) {
    enabled = on;
    if (on) _curDb = 0; // qalxma sıfırdan: qulağa ani zərbə olmasın
    _startRamp();
    _save();
    notifyListeners();
  }

  void setMult(double m) {
    mult = m.clamp(1.0, 10.0).toDouble();
    if (mult > 1.001 && !enabled) {
      enabled = true;
      _curDb = 0;
    }
    _autoTune();
    _startRamp();
    _save();
    notifyListeners();
  }

  /// Sürüşdürmə zamanı yalnız göstəriş (tətbiq və saxlama onChangeEnd-də).
  void previewMult(double v) {
    mult = v.clamp(1.0, 10.0).toDouble();
    notifyListeners();
  }

  void previewExtra(double v) {
    extraDb = v.clamp(0.0, 12.0).toDouble();
    notifyListeners();
  }

  void setClarity(String name) {
    if (!kClarity.containsKey(name)) return;
    clarity = name;
    _fillBands();
    _startRamp();
    _save();
    notifyListeners();
  }

  void setExtraDb(double v) {
    extraDb = v.clamp(0.0, 12.0).toDouble();
    _startRamp();
    _save();
    notifyListeners();
  }

  /// Qabaqcıl sürüşdürücülər: dəyər dərhal tətbiq olunur, saxlama [commit]-də.
  void setAdvanced({
    double? ratio,
    double? threshold,
    double? limThreshold,
    double? limCeiling,
    int? band,
    double? bandValue,
    bool commit = false,
  }) {
    if (ratio != null) this.ratio = ratio;
    if (threshold != null) this.threshold = threshold;
    if (limThreshold != null) this.limThreshold = limThreshold;
    if (limCeiling != null) this.limCeiling = limCeiling;
    if (band != null && bandValue != null) bandGain[band] = bandValue;
    _push();
    notifyListeners();
    if (commit) _save();
  }

  /// Əmsala görə kompressoru avtomatik qurur: orta səviyyəli musiqi də həqiqətən N dəfə
  /// güclənsin, yalnız zirvələr tutulsun. Çox aşağı hədd + yüksək ratio səsi əksinə azaldardı.
  void _autoTune() {
    final db = 20 * math.log(mult) / math.ln10;
    if (mult <= 1.001) {
      ratio = 1;
      threshold = -12;
    } else {
      ratio = (1.5 + 0.25 * mult).clamp(1.0, 4.0).toDouble();
      threshold = -10 - db * 0.4; // 10x -> -18 dB
    }
    limThreshold = -3;
    limCeiling = -1;
  }

  void _fillBands() {
    final g = kClarity[clarity]!;
    for (var i = 0; i < kBands; i++) {
      bandGain[i] = g[i];
    }
  }

  // ---- tətbiq ----
  void _push() {
    SoloudEngine.instance.configure(
      fx: enabled,
      bands: bandGain,
      makeupDb: _curDb,
      ratio: ratio,
      threshold: threshold,
      limThreshold: limThreshold,
      limCeiling: limCeiling,
    );
  }

  /// Gücləndirməni ~300 ms-də yumşaq qaldırır/endirir (1x -> 10x ani sıçrayış olmasın).
  void _startRamp() {
    _ramp?.cancel();
    final target = enabled ? targetDb : 0.0;
    if (!enabled) {
      _curDb = 0;
      _push();
      return;
    }
    _push();
    final start = _curDb;
    var i = 0;
    const steps = 10;
    _ramp = Timer.periodic(const Duration(milliseconds: 30), (t) {
      i++;
      _curDb = start + (target - start) * i / steps;
      SoloudEngine.instance.setMakeup(_curDb);
      if (i >= steps) {
        _curDb = target;
        t.cancel();
      }
    });
  }
}
