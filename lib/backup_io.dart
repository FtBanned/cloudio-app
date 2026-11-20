import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'backup_types.dart';

/// Yedək faylı (.cloudio) sadə bir qutudur, böyük səs faylları yaddaşa yüklənmədən
/// bir-bir yazılır/oxunur:
///   8 bayt  "CLOUDIO1"
///   təkrar: [4 bayt ad uzunluğu][ad][8 bayt məlumat uzunluğu][məlumat]
///   sonda:  [4 bayt 0]
/// Girişlər: manifest.json, db.json, audio/<fayl adı> ...
const _magic = 'CLOUDIO1';
const _maxManifestBytes = 20 * 1024 * 1024;

Future<Directory> _audioDir() async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}/audio');
}

/// Tətbiq qovluğundakı səs faylları (ada görə sıralanmış).
Future<List<BackupAudioEntry>> listAudioFiles() async {
  final dir = await _audioDir();
  if (!await dir.exists()) return [];
  final out = <BackupAudioEntry>[];
  await for (final e in dir.list(followLinks: false)) {
    if (e is File) {
      out.add(BackupAudioEntry(e.uri.pathSegments.last, await e.length()));
    }
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

Uint8List _u32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();
Uint8List _u64(int v) => (ByteData(8)..setUint64(0, v)).buffer.asUint8List();

Future<void> _writeHeader(RandomAccessFile raf, String name, int len) async {
  final nb = utf8.encode(name);
  final b = BytesBuilder(copy: false)
    ..add(_u32(nb.length))
    ..add(nb)
    ..add(_u64(len));
  await raf.writeFrom(b.takeBytes());
}

Future<void> _writeEntry(RandomAccessFile raf, String name, List<int> data) async {
  await _writeHeader(raf, name, data.length);
  await raf.writeFrom(data);
}

/// Yedək faylını müvəqqəti qovluqda yaradır və yolunu qaytarır.
Future<String> writeBackupFile({
  required String dbJson,
  required bool full,
  required int songCount,
  required int playlistCount,
  required String appVersion,
  void Function(double progress)? onProgress,
}) async {
  final audio = full ? await listAudioFiles() : <BackupAudioEntry>[];
  final dbBytes = utf8.encode(dbJson);
  var audioBytes = 0;
  for (final a in audio) {
    audioBytes += a.size;
  }
  final manifest = BackupManifest(
    format: kBackupFormat,
    full: full,
    createdMs: DateTime.now().millisecondsSinceEpoch,
    appVersion: appVersion,
    songCount: songCount,
    playlistCount: playlistCount,
    dbBytes: dbBytes.length,
    audioBytes: audioBytes,
    audio: audio,
  );

  final tmp = await getTemporaryDirectory();
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${now.year}-${two(now.month)}-${two(now.day)}';
  final path =
      '${tmp.path}/Cloudio-yedek-$stamp-${full ? 'tam' : 'hafif'}.$kBackupExt';
  final out = File(path);
  if (await out.exists()) await out.delete();

  final audioDir = await _audioDir();
  final raf = await out.open(mode: FileMode.write);
  var ok = false;
  try {
    await raf.writeFrom(ascii.encode(_magic));
    await _writeEntry(
        raf, 'manifest.json', utf8.encode(jsonEncode(manifest.toJson())));
    await _writeEntry(raf, 'db.json', dbBytes);

    final total = dbBytes.length + audioBytes;
    var done = dbBytes.length;
    var lastReported = -1.0;
    void report() {
      if (onProgress == null || total <= 0) return;
      final p = done / total;
      if (p - lastReported >= 0.005 || p >= 1) {
        lastReported = p;
        onProgress(p.clamp(0.0, 1.0));
      }
    }

    report();
    for (final a in audio) {
      final f = File('${audioDir.path}/${a.name}');
      await _writeHeader(raf, 'audio/${a.name}', a.size);
      var copied = 0;
      await for (final chunk in f.openRead()) {
        copied += chunk.length;
        if (copied > a.size) {
          throw BackupException('"${a.name}" yedekleme sırasında değişti');
        }
        await raf.writeFrom(chunk);
        done += chunk.length;
        report();
      }
      if (copied != a.size) {
        throw BackupException('"${a.name}" yedekleme sırasında değişti');
      }
    }
    await raf.writeFrom(_u32(0));
    await raf.flush();
    ok = true;
  } finally {
    await raf.close();
    if (!ok) {
      try {
        await out.delete();
      } catch (_) {}
    }
  }
  onProgress?.call(1);
  return path;
}

Future<int> backupFileSize(String path) => File(path).length();

// ------------------------------------------------------------------ oxuma

Future<Uint8List> _readExact(RandomAccessFile raf, int n) async {
  final out = Uint8List(n);
  var got = 0;
  while (got < n) {
    final c = await raf.readInto(out, got, n);
    if (c == 0) throw const BackupException('Yedek dosyası yarım kalmış');
    got += c;
  }
  return out;
}

Future<void> _checkMagic(RandomAccessFile raf) async {
  final Uint8List m;
  try {
    m = await _readExact(raf, _magic.length);
  } on BackupException {
    throw const BackupException('Bu bir Cloudio yedeği değil');
  }
  if (ascii.decode(m, allowInvalid: true) != _magic) {
    throw const BackupException('Bu bir Cloudio yedeği değil');
  }
}

class _Entry {
  final String name;
  final int len;
  const _Entry(this.name, this.len);
}

/// null: son işarəsi.
Future<_Entry?> _readHeader(RandomAccessFile raf) async {
  final nl = ByteData.sublistView(await _readExact(raf, 4)).getUint32(0);
  if (nl == 0) return null;
  if (nl > 1024) throw const BackupException('Yedek dosyası bozuk');
  final name = utf8.decode(await _readExact(raf, nl), allowMalformed: true);
  final len = ByteData.sublistView(await _readExact(raf, 8)).getUint64(0);
  return _Entry(name, len);
}

/// Yalnız başlıqdakı manifesti oxuyur (səs fayllarına toxunmur). Yedək etibarsızdırsa
/// [BackupException] atır.
Future<BackupManifest> readBackupManifest(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw const BackupException('Dosya bulunamadı');
  }
  final raf = await file.open();
  try {
    await _checkMagic(raf);
    final e = await _readHeader(raf);
    if (e == null || e.name != 'manifest.json' || e.len > _maxManifestBytes) {
      throw const BackupException('Yedek dosyası bozuk');
    }
    final bytes = await _readExact(raf, e.len);
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const BackupException('Yedek dosyası bozuk');
    }
    return BackupManifest.fromJson(json);
  } finally {
    await raf.close();
  }
}

bool _safeName(String n) =>
    n.isNotEmpty &&
    n != '.' &&
    n != '..' &&
    !n.contains('/') &&
    !n.contains('\\') &&
    !n.contains('\u0000');

/// Yedəyi müvəqqəti qovluğa açır və yoxlayır (heç nə hələ əvəz olunmur).
Future<StagedBackup> extractBackup(
  String path, {
  void Function(double progress)? onProgress,
}) async {
  final total = await File(path).length();
  final tmp = await getTemporaryDirectory();
  final stage = Directory('${tmp.path}/cloudio_restore');
  if (await stage.exists()) await stage.delete(recursive: true);
  final stageAudio = Directory('${stage.path}/audio');
  await stageAudio.create(recursive: true);

  final raf = await File(path).open();
  try {
    await _checkMagic(raf);
    BackupManifest? manifest;
    Map<String, Object?>? db;
    final got = <String, int>{};
    var lastReported = -1.0;

    while (true) {
      final e = await _readHeader(raf);
      if (e == null) break;
      if (e.name == 'manifest.json') {
        if (e.len > _maxManifestBytes) {
          throw const BackupException('Yedek dosyası bozuk');
        }
        final b = await _readExact(raf, e.len);
        manifest = BackupManifest.fromJson(jsonDecode(utf8.decode(b)));
      } else if (e.name == 'db.json') {
        final b = await _readExact(raf, e.len);
        final decoded = jsonDecode(utf8.decode(b));
        if (decoded is! Map) throw const BackupException('Yedek dosyası bozuk');
        db = Map<String, Object?>.from(decoded);
      } else if (e.name.startsWith('audio/')) {
        final name = e.name.substring(6);
        if (!_safeName(name)) throw const BackupException('Yedek dosyası bozuk');
        final out = await File('${stageAudio.path}/$name').open(mode: FileMode.write);
        try {
          var left = e.len;
          while (left > 0) {
            final n = left < 1048576 ? left : 1048576;
            await out.writeFrom(await _readExact(raf, n));
            left -= n;
            final p = (await raf.position()) / total;
            if (onProgress != null && p - lastReported >= 0.005) {
              lastReported = p;
              onProgress(p.clamp(0.0, 1.0));
            }
          }
        } finally {
          await out.close();
        }
        got[name] = e.len;
      } else {
        await raf.setPosition(await raf.position() + e.len); // tanınmayan giriş
      }
    }

    if (manifest == null || db == null) {
      throw const BackupException('Yedek dosyası bozuk');
    }
    if (manifest.full) {
      if (got.length != manifest.audio.length) {
        throw const BackupException('Yedekteki şarkı dosyaları eksik');
      }
      for (final a in manifest.audio) {
        if (got[a.name] != a.size) {
          throw const BackupException('Yedekteki şarkı dosyaları eksik veya bozuk');
        }
      }
    }
    onProgress?.call(1);
    return StagedBackup(stage.path, db, manifest);
  } finally {
    await raf.close();
  }
}

Future<void> _moveDir(Directory from, Directory to) async {
  try {
    await from.rename(to.path);
  } on FileSystemException {
    // fərqli disk bölməsi: kopyala və sil
    await to.create(recursive: true);
    await for (final e in from.list(followLinks: false)) {
      if (e is File) {
        await e.copy('${to.path}/${e.uri.pathSegments.last}');
        await e.delete();
      }
    }
  }
}

/// Köhnə səs qovluğunu kənara çəkir, açılmış yedəyin səs qovluğunu onun yerinə qoyur.
Future<AudioSwap> swapInAudio(StagedBackup s) async {
  final base = await getApplicationSupportDirectory();
  final audio = Directory('${base.path}/audio');
  final old = Directory('${base.path}/audio_old');
  if (await old.exists()) await old.delete(recursive: true);
  final hadOld = await audio.exists();
  if (hadOld) await audio.rename(old.path);
  try {
    await _moveDir(Directory('${s.dirPath}/audio'), audio);
    if (!await audio.exists()) await audio.create(recursive: true);
  } catch (_) {
    if (await audio.exists()) await audio.delete(recursive: true);
    if (hadOld) await old.rename(audio.path);
    rethrow;
  }
  return AudioSwap(
    commit: () async {
      if (await old.exists()) await old.delete(recursive: true);
    },
    rollback: () async {
      if (await audio.exists()) await audio.delete(recursive: true);
      if (await old.exists()) await old.rename(audio.path);
    },
  );
}

/// Müvəqqəti qovluqdakı açılmış yedəyi və yaradılmış yedək fayllarını silir.
Future<void> deleteBackupTemp() async {
  try {
    final tmp = await getTemporaryDirectory();
    final stage = Directory('${tmp.path}/cloudio_restore');
    if (await stage.exists()) await stage.delete(recursive: true);
    await for (final e in tmp.list(followLinks: false)) {
      if (e is File) {
        final n = e.uri.pathSegments.last;
        if (n.startsWith('Cloudio-yedek-') && n.endsWith('.$kBackupExt')) {
          await e.delete();
        }
      }
    }
  } catch (_) {}
}

/// Seçilmiş fayl müvəqqəti qovluqdadırsa (iOS seçici kopyalayır) silir; istifadəçinin
/// öz faylına toxunmur.
Future<void> deleteIfInTemp(String path) async {
  try {
    final tmp = await getTemporaryDirectory();
    if (path.startsWith(tmp.path)) await File(path).delete();
  } catch (_) {}
}
