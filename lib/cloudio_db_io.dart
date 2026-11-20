import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/utils/sembast_import_export.dart';

/// Telefonda (iOS/Android) və masaüstündə baza tətbiqin xüsusi qovluğundakı
/// "cloudio.db" faylında saxlanır (tətbiq bağlanıb açılsa da qalır).
Future<Database?> openCloudioDb() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return databaseFactoryIo.openDatabase('${dir.path}/cloudio.db');
}

/// Yedəkdən oxunmuş məzmunla bazanı tamamilə əvəz edir (köhnə baza əvvəlcə .bak kimi
/// saxlanır, xəta olarsa geri qaytarılır). Çağırmazdan əvvəl köhnə baza bağlanmalıdır.
Future<Database?> importCloudioDb(Map<String, Object?> content) async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final path = '${dir.path}/cloudio.db';
  final cur = File(path);
  final bak = File('$path.bak');
  if (await bak.exists()) await bak.delete();
  if (await cur.exists()) await cur.rename(bak.path);
  try {
    final db = await importDatabase(content, databaseFactoryIo, path);
    if (await bak.exists()) await bak.delete();
    return db;
  } catch (_) {
    if (await cur.exists()) await cur.delete();
    if (await bak.exists()) await bak.rename(path);
    rethrow;
  }
}
