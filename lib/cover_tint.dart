import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show HSVColor;

/// Kapağı 16x16'ya küçültüp ortalama rengini bulur. Okunamazsa null döner.
Future<ui.Color?> coverTint(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 16,
      targetHeight: 16,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;

    var r = 0, g = 0, b = 0, n = 0;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      r += data.getUint8(i);
      g += data.getUint8(i + 1);
      b += data.getUint8(i + 2);
      n++;
    }
    frame.image.dispose();
    codec.dispose();
    if (n == 0) return null;
    return ui.Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  } catch (_) {
    return null;
  }
}

/// Seçilen resmi doğrular; çok büyükse 1000px'e küçültüp PNG yapar (veritabanı şişmesin).
/// Okunamazsa null döner.
Future<Uint8List?> normalizeCover(Uint8List bytes) async {
  try {
    if (bytes.length <= 700 * 1024) {
      // küçük dosya: sadece çözülebildiğini doğrula
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 16);
      final f = await codec.getNextFrame();
      f.image.dispose();
      codec.dispose();
      return bytes;
    }
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1000);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Kapağın iki əsas rəngi: primary = ən "canlı" dominant ton, secondary = ondan fərqli ikinci ton
/// (tapılmasa primary ilə eynidir). Ortalama rəngdən fərqli olaraq boz/palçıq rəng çıxarmır.
class CoverPalette {
  final ui.Color primary;
  final ui.Color secondary;
  const CoverPalette(this.primary, this.secondary);
}

final _paletteCache = Expando<CoverPalette>();

/// Eyni kapaq baytları üçün nəticə yadda qalır. Oxunmazsa null.
Future<CoverPalette?> coverPalette(Uint8List bytes) async {
  final cached = _paletteCache[bytes];
  if (cached != null) return cached;
  try {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 32,
      targetHeight: 32,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;

    const bins = 12; // hər tonlama 30 dərəcə
    final w = List<double>.filled(bins, 0);
    final rs = List<double>.filled(bins, 0);
    final gs = List<double>.filled(bins, 0);
    final bs = List<double>.filled(bins, 0);
    var ar = 0.0, ag = 0.0, ab = 0.0, an = 0.0;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      final r = data.getUint8(i), g = data.getUint8(i + 1), b = data.getUint8(i + 2);
      ar += r;
      ag += g;
      ab += b;
      an++;
      final hsv = HSVColor.fromColor(ui.Color.fromARGB(255, r, g, b));
      if (hsv.value < 0.15 || hsv.saturation < 0.15) continue; // qara / boz piksel
      final weight = hsv.saturation * (0.3 + hsv.value);
      final bin = (hsv.hue / (360 / bins)).floor() % bins;
      w[bin] += weight;
      rs[bin] += r * weight;
      gs[bin] += g * weight;
      bs[bin] += b * weight;
    }
    if (an == 0) return null;
    final avg = ui.Color.fromARGB(255, ar ~/ an, ag ~/ an, ab ~/ an);

    var best = 0;
    for (var i = 1; i < bins; i++) {
      if (w[i] > w[best]) best = i;
    }
    ui.Color binColor(int i) => ui.Color.fromARGB(
        255, (rs[i] / w[i]).round(), (gs[i] / w[i]).round(), (bs[i] / w[i]).round());

    CoverPalette pal;
    if (w[best] < 0.5) {
      pal = CoverPalette(avg, avg); // demək olar ki, ağ-qara kapaq
    } else {
      final primary = binColor(best);
      var second = -1;
      for (var i = 0; i < bins; i++) {
        final d = (i - best).abs();
        final dist = d > bins ~/ 2 ? bins - d : d;
        if (dist < 2 || w[i] < w[best] * 0.25) continue;
        if (second < 0 || w[i] > w[second]) second = i;
      }
      pal = CoverPalette(primary, second < 0 ? primary : binColor(second));
    }
    _paletteCache[bytes] = pal;
    return pal;
  } catch (_) {
    return null;
  }
}
