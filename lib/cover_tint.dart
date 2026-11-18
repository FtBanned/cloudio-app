import 'dart:typed_data';
import 'dart:ui' as ui;

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
