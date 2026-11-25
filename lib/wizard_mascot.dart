import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:material_ui/material_ui.dart';

/// Büyücünün ruh hali (animasiya növü).
enum WizardMood {
  /// sakit: nəfəs alır, göz qırpır, çubuq yüngülcə yellənir
  idle,

  /// danışır: bədən kiçik-kiçik "səkir"
  talk,

  /// əl yellədir, çubuqdan qığılcım saçılır
  wave,

  /// sevinir: hoppanır, iki əli yuxarı
  cheer,
}

/// Cloudio-nun pixel-art büyücü maskotu. Şəkil faylı yoxdur: hər şey koddan çəkilir,
/// ona görə əl, çubuq, göz və s. ayrı-ayrı hərəkət edə bilir.
class WizardMascot extends StatefulWidget {
  final double height;
  final WizardMood mood;
  const WizardMascot({super.key, this.height = 160, this.mood = WizardMood.idle});

  @override
  State<WizardMascot> createState() => _WizardMascotState();
}

class _WizardMascotState extends State<WizardMascot> with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  late final Ticker _ticker;
  double _moodStart = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _clock.value = d.inMicroseconds / 1e6)..start();
  }

  @override
  void didUpdateWidget(WizardMascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _moodStart = _clock.value; // hoppanma yenidən başlasın
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.height * _WizardPainter.w / _WizardPainter.h,
      height: widget.height,
      child: CustomPaint(painter: _WizardPainter(_clock, widget.mood, _moodStart)),
    );
  }
}

class _WizardPainter extends CustomPainter {
  // Rəsm şəbəkə vahidləri ilə çəkilir (1 vahid = orijinal şəkildə ~10 piksel), sonra ölçüyə görə böyüdülür.
  static const double w = 22.5;
  static const double h = 20.2;

  _WizardPainter(this.clock, this.mood, this.moodStart) : super(repaint: clock);

  final ValueListenable<double> clock;
  final WizardMood mood;
  final double moodStart;

  static const _skin = Color(0xFFDB7759);
  static const _skinLight = Color(0xFFE08F72);
  static const _robe = Color(0xFF4B3E8D);
  static const _robeDark = Color(0xFF3C2F78);
  static const _star = Color(0xFFF2C14E);
  static const _eye = Color(0xFF14111F);
  static const _wood = Color(0xFF8C6A3E);

  static Paint _p(Color c) => Paint()
    ..color = c
    ..isAntiAlias = true;

  void _r(Canvas c, double x, double y, double ww, double hh, Paint p) =>
      c.drawRect(Rect.fromLTWH(x, y, ww, hh), p);

  @override
  void paint(Canvas canvas, Size size) {
    final time = clock.value;
    final skin = _p(_skin);
    final skinLight = _p(_skinLight);
    final robe = _p(_robe);
    final robeDark = _p(_robeDark);
    final star = _p(_star);
    final eye = _p(_eye);
    final wood = Paint()
      ..color = _wood
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..isAntiAlias = true;

    final s = size.height / h;
    canvas.save();
    canvas.scale(s, s);

    // ---- hoppanma (cheer) ----
    final k = time - moodStart;
    double jump = 0;
    if (mood == WizardMood.cheer && k < 1.6) {
      jump = -math.sin(k * math.pi * 3).abs() * 2.6 * (1 - k / 1.6);
    }

    // ---- kölgə (yerdə qalır, hoppananda kiçilir) ----
    final shadowK = 1 + jump * 0.08;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(9.9, 19.2), width: 14.5 * shadowK, height: 1.3 * shadowK),
      Paint()..color = const Color(0x33000000),
    );

    canvas.translate(0, jump);

    // ---- danışanda yüngül "səkmə" (ayaqların dibindən şaquli sıxılma) ----
    double sq = 0;
    if (mood == WizardMood.talk) {
      final wob = math.sin(time * 13);
      sq = 0.035 * wob * wob;
    }
    canvas.translate(9.9, 18.3);
    canvas.scale(1 - sq * 0.5, 1 + sq);
    canvas.translate(-9.9, -18.3);

    // ---- ayaqlar (4 ədəd) ----
    for (final x in const [5.2, 7.6, 12.3, 14.8]) {
      _r(canvas, x, 14.3, 1.7, 4.0, skin);
    }

    // ---- yuxarı hissə nəfəs alır ----
    final bob = math.sin(time * 2.4) * 0.18;
    canvas.save();
    canvas.translate(0, bob);

    // sol qol (çiyindən fırlanır; cheer-də yuxarı qalxır)
    final leftAng = mood == WizardMood.cheer
        ? 0.9 + math.sin(time * 10) * 0.25
        : math.sin(time * 2.4 + 1) * 0.04;
    canvas.save();
    canvas.translate(3.6, 9.9);
    canvas.rotate(leftAng);
    _r(canvas, -2.7, -1.3, 2.8, 2.6, skin);
    canvas.restore();

    // baş + gövdə (narıncı blok, üst zolağı bir az açıq)
    _r(canvas, 3.4, 4.4, 13.0, 5.9, skin);
    _r(canvas, 3.4, 4.4, 13.0, 1.0, skinLight);

    // gözlər (baxış yüngülcə sürüşür, arabir qırpır)
    final phase = time % 3.6;
    final blink = (phase > 3.42 && phase < 3.6) ? 0.15 : 1.0;
    final look = math.sin(time * 0.8) * 0.2;
    final eh = 2.5 * blink;
    final ey = 7.1 + (2.5 - eh) / 2;
    _r(canvas, 7.5 + look, ey, 1.45, eh, eye);
    _r(canvas, 12.0 + look, ey, 1.45, eh, eye);

    // paltar (bənövşəyi, üst zolağı tünd)
    _r(canvas, 3.4, 10.2, 13.0, 4.3, robe);
    _r(canvas, 3.4, 10.2, 13.0, 0.6, robeDark);
    _r(canvas, 7.1, 11.8, 0.9, 0.9, star);
    _r(canvas, 5.3, 13.0, 0.8, 0.8, star);
    _r(canvas, 12.0, 12.5, 0.9, 0.9, star);

    // papaq: üçbucaq, ucu yüngülcə yellənir; altında tünd kənar
    final tipSway = math.sin(time * 2.4 + 0.5) * 0.2;
    final hat = Path()
      ..moveTo(6.6, 3.8)
      ..lineTo(9.9 + tipSway, 0.2)
      ..lineTo(13.2, 3.8)
      ..close();
    canvas.drawPath(hat, robe);
    _r(canvas, 4.6, 3.7, 10.7, 1.1, robeDark);
    _r(canvas, 9.3 + tipSway * 0.8, 0.9, 1.0, 1.0, star);
    _r(canvas, 7.8, 2.5, 0.8, 0.8, star);
    _r(canvas, 11.1, 2.2, 0.8, 0.8, star);

    // sağ qol + çubuq (hamısı çiyin ətrafında fırlanır)
    final double rightAng = switch (mood) {
      WizardMood.wave => -0.4 + math.sin(time * 9) * 0.35,
      WizardMood.cheer => -0.9 + math.sin(time * 10) * 0.25,
      WizardMood.talk => math.sin(time * 4) * 0.1,
      WizardMood.idle => math.sin(time * 2.4 + 0.7) * 0.04,
    };
    const pivot = Offset(16.3, 9.9);
    const wandBase = Offset(1.5, 0.5);
    const wandTip = Offset(3.8, -4.5);
    const starAt = Offset(3.9, -5.3);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(rightAng);
    _r(canvas, -0.1, -1.3, 2.7, 2.6, skin);
    canvas.drawLine(wandBase, wandTip, wood);
    // çubuğun ucundakı fırlanmış ulduz (qızılı çərçivə + açıq mərkəz)
    canvas.save();
    canvas.translate(starAt.dx, starAt.dy);
    canvas.rotate(0.5);
    _r(canvas, -0.75, -0.75, 1.5, 1.5, star);
    _r(canvas, -0.3, -0.3, 0.6, 0.6, _p(const Color(0xFFFFF3C9)));
    canvas.restore();
    canvas.restore();

    // ---- qığılcımlar (çubuğun dünya koordinatındakı ucundan) ----
    final c = math.cos(rightAng);
    final sn = math.sin(rightAng);
    final tip = Offset(
      pivot.dx + starAt.dx * c - starAt.dy * sn,
      pivot.dy + starAt.dx * sn + starAt.dy * c,
    );
    final lively = mood == WizardMood.wave || mood == WizardMood.cheer;
    final n = lively ? 5 : 2;
    for (var i = 0; i < n; i++) {
      final p = (time * (lively ? 1.3 : 0.7) + i / n) % 1.0;
      final a = i * 2.4 + 0.5;
      final d = p * 2.4;
      final o = tip + Offset(math.cos(a) * d, math.sin(a) * d - p * 1.2);
      final sz = 0.7 * (1 - p);
      canvas.drawRect(
        Rect.fromLTWH(o.dx - sz / 2, o.dy - sz / 2, sz, sz),
        _p(_star.withValues(alpha: (1 - p).clamp(0.0, 1.0))),
      );
    }

    canvas.restore(); // bob
    canvas.restore(); // scale
  }

  @override
  bool shouldRepaint(_WizardPainter old) => old.mood != mood || old.moodStart != moodStart;
}
