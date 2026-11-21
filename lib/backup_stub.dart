import 'backup_types.dart';

/// Web-də yedək yoxdur (səs faylları brauzer bazasındadır). Telefon üçün backup_io.dart.
BackupException get _unsupported => const BackupException('Yedekleme bu platformda desteklenmiyor');

Future<List<BackupAudioEntry>> listAudioFiles() async => [];

Future<String> writeBackupFile({
  required String dbJson,
  required bool full,
  required int songCount,
  required int playlistCount,
  required String appVersion,
  void Function(double progress)? onProgress,
}) async => throw _unsupported;

Future<int> backupFileSize(String path) async => 0;

Future<BackupManifest> readBackupManifest(String path) async => throw _unsupported;

Future<StagedBackup> extractBackup(
  String path, {
  void Function(double progress)? onProgress,
}) async => throw _unsupported;

Future<AudioSwap> swapInAudio(StagedBackup s) async => throw _unsupported;

Future<void> deleteBackupTemp() async {}

Future<void> deleteIfInTemp(String path) async {}
