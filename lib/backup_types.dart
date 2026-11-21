// Yedək sisteminin platformadan asılı olmayan tipləri (telefon və web üçün eyni).

const kBackupFormat = 1;
const kBackupExt = 'cloudio';
const kAppVersion = '1.0.0';

/// İstifadəçiyə göstərilə bilən yedək xətası (mesaj Türkçə, ekranda olduğu kimi çıxır).
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

/// "412,3 MB" kimi oxunaqlı ölçü.
String formatBytes(int b) {
  if (b < 1024) return '$b B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = b / 1024.0;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${s.replaceAll('.', ',')} ${units[i]}';
}

class BackupAudioEntry {
  final String name; // tətbiq qovluğundakı fayl adı (məs. 12.mp3)
  final int size;
  const BackupAudioEntry(this.name, this.size);

  Map<String, Object?> toJson() => {'n': name, 's': size};

  static BackupAudioEntry fromJson(Object? raw) {
    if (raw is! Map) throw const BackupException('Yedek dosyası bozuk');
    final n = raw['n'];
    final s = raw['s'];
    if (n is! String || s is! int) {
      throw const BackupException('Yedek dosyası bozuk');
    }
    return BackupAudioEntry(n, s);
  }
}

/// Yedək faylının başındakı təsvir: növü, tarixi, mahnı sayı, ölçüləri.
class BackupManifest {
  final int format;
  final bool full; // true: səs faylları da içindədir
  final int createdMs;
  final String appVersion;
  final int songCount;
  final int playlistCount;
  final int dbBytes;
  final int audioBytes;
  final List<BackupAudioEntry> audio;

  const BackupManifest({
    required this.format,
    required this.full,
    required this.createdMs,
    required this.appVersion,
    required this.songCount,
    required this.playlistCount,
    required this.dbBytes,
    required this.audioBytes,
    required this.audio,
  });

  int get audioCount => audio.length;
  DateTime get created => DateTime.fromMillisecondsSinceEpoch(createdMs);

  Map<String, Object?> toJson() => {
    'format': format,
    'full': full,
    'created': createdMs,
    'app': appVersion,
    'songs': songCount,
    'playlists': playlistCount,
    'dbBytes': dbBytes,
    'audioBytes': audioBytes,
    'audio': [for (final a in audio) a.toJson()],
  };

  static BackupManifest fromJson(Object? raw) {
    if (raw is! Map) throw const BackupException('Yedek dosyası bozuk');
    try {
      final format = raw['format'] as int;
      if (format > kBackupFormat) {
        throw const BackupException(
          'Bu yedek Cloudio\'nun daha yeni bir sürümüyle alınmış. Uygulamayı güncelle.',
        );
      }
      return BackupManifest(
        format: format,
        full: raw['full'] as bool,
        createdMs: raw['created'] as int,
        appVersion: raw['app'] as String? ?? '',
        songCount: raw['songs'] as int? ?? 0,
        playlistCount: raw['playlists'] as int? ?? 0,
        dbBytes: raw['dbBytes'] as int? ?? 0,
        audioBytes: raw['audioBytes'] as int? ?? 0,
        audio: [for (final e in (raw['audio'] as List? ?? const [])) BackupAudioEntry.fromJson(e)],
      );
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException('Yedek dosyası bozuk');
    }
  }
}

/// Yedək yaratmazdan əvvəl hesablanmış plan: iki rejimin təxmini ölçüsü ekranda göstərilir.
class BackupPlan {
  final String dbJson; // bütün məlumat bazası (mahnı məlumatları, üzlüklər, siyahılar, ...)
  final int dbBytes;
  final int audioBytes;
  final int audioCount;
  final int songCount;
  final int playlistCount;

  const BackupPlan({
    required this.dbJson,
    required this.dbBytes,
    required this.audioBytes,
    required this.audioCount,
    required this.songCount,
    required this.playlistCount,
  });

  /// Hafif yedek: yalnız məlumatlar.
  int get lightSize => dbBytes + 2048;

  /// Tam yedek: məlumatlar + bütün səs faylları.
  int get fullSize => dbBytes + audioBytes + 2048 + audioCount * 120;
}

/// Bərpa üçün müvəqqəti qovluğa açılmış yedək.
class StagedBackup {
  final String dirPath;
  final Map<String, Object?> db;
  final BackupManifest manifest;
  const StagedBackup(this.dirPath, this.db, this.manifest);
}

/// Səs qovluğunun dəyişdirilməsi: uğurlu olarsa commit, xəta olarsa rollback.
class AudioSwap {
  final Future<void> Function() commit;
  final Future<void> Function() rollback;
  const AudioSwap({required this.commit, required this.rollback});
}
