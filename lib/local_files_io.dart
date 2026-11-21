import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

/// Telefonda mahnı faylları tətbiqin öz qovluğuna köçürülür və orada qalır.
/// Bazada yalnız fayl ADI saxlanır (tam yol yox): iOS tətbiqi yenidən
/// quranda/yeniləyəndə qovluğun tam yolu dəyişə bilər.
Directory? _audioDir;

Future<void> initLocalFiles() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/audio');
  await dir.create(recursive: true);
  _audioDir = dir;
}

/// Faylın hazırkı tam yolu; fayl yoxdursa null.
String? audioPathFor(String? file) {
  final dir = _audioDir;
  if (dir == null || file == null || file.isEmpty) return null;
  final p = '${dir.path}/$file';
  return File(p).existsSync() ? p : null;
}

/// Seçilmiş (müvəqqəti) faylı tətbiqin qovluğuna köçürür. Uğurlu olarsa fayl adını qaytarır.
Future<String?> importAudioFile({required String sourcePath, required String fileName}) async {
  try {
    if (_audioDir == null) await initLocalFiles();
    await File(sourcePath).copy('${_audioDir!.path}/$fileName');
    return fileName;
  } catch (e) {
    debugPrint('[Cloudio] fayl köçürülmədi ($fileName): $e');
    return null;
  }
}

Future<void> deleteAudioFile(String? file) async {
  try {
    final p = audioPathFor(file);
    if (p != null) await File(p).delete();
  } catch (e) {
    debugPrint('[Cloudio] fayl silinmədi ($file): $e');
  }
}

/// Kilid ekranı üçün kapağı müvəqqəti fayl kimi yazır və onun linkini qaytarır.
/// [key] eyni olarsa fayl təkrar yazılmır.
Future<Uri?> writeCoverFile(String key, Uint8List bytes) async {
  try {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/cover_$key.jpg');
    if (!await f.exists()) await f.writeAsBytes(bytes, flush: true);
    return f.uri;
  } catch (e) {
    debugPrint('[Cloudio] kapaq faylı yazılmadı: $e');
    return null;
  }
}

/// Süre hesaplamak için şarkı dosyasını okur (yoksa null).
Future<Uint8List?> readAudioBytes(String? path) async {
  if (path == null) return null;
  try {
    return await File(path).readAsBytes();
  } catch (e) {
    debugPrint('[Cloudio] fayl oxunmadı ($path): $e');
    return null;
  }
}
