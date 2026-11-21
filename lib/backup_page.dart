import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_stub.dart' if (dart.library.io) 'backup_io.dart' show backupFileSize;
import 'backup_reminder.dart';
import 'backup_types.dart';
import 'main.dart' show kBg, kCard, kGreen, kText38, kText54, kText60, kText70;
import 'player_controller.dart';

/// "Yedekle ve geri yükle" səhifəsini açır (Ayarlar və boş Ana səhifədən çağırılır).
void openBackupPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const BackupPage()),
  );
}

class _Prog {
  final double value; // 0..1, null yerinə -1: bilinmir
  final String text;
  const _Prog(this.value, this.text);
}

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yedekle ve geri yükle',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final missing = c.missingAudioCount;
          return ListView(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, 24 + MediaQuery.of(context).padding.bottom),
            children: [
              Text(
                'Uygulamayı silince kitaplığın da silinir. Önce yedek al, yedeği '
                'Dosyalar\'a (iCloud Drive) kaydet; uygulamayı yeniden indirince '
                'buradan geri yükle.',
                style: TextStyle(color: kText60, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                'Yedeğe girenler: şarkı bilgileri (ad, sanatçı, albüm, janr, yıl, sıra), '
                'kapaklar, sözler, çalma listeleri, beğeniler, kitaplık sırası, dinleme '
                'istatistiği, ayarlar, tema ve profil.',
                style: TextStyle(color: kText54, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              if (!c.backupSupported) ...[
                Text('Yedekleme bu platformda kullanılamıyor.',
                    style: TextStyle(color: kText60)),
                if (kBackupReminderWebTest) ...[
                  const SizedBox(height: 10),
                  const BackupReminderSettings(),
                ],
              ] else ...[
                const BackupReminderSettings(),
                const SizedBox(height: 10),
                _ActionCard(
                  icon: Icons.cloud_upload_outlined,
                  title: 'Yedek oluştur',
                  subtitle: 'Tam (şarkılarla) ya da hafif (sadece bilgiler)',
                  onTap: c.loading ? null : () => _createFlow(context),
                ),
                const SizedBox(height: 10),
                _ActionCard(
                  icon: Icons.restore,
                  title: 'Yedekten geri yükle',
                  subtitle: 'Mevcut kitaplığın tamamen değiştirilir',
                  onTap: c.loading ? null : () => _restoreFlow(context),
                ),
                if (missing > 0) ...[
                  const SizedBox(height: 10),
                  _ActionCard(
                    icon: Icons.link,
                    title: '$missing şarkının dosyası eksik',
                    subtitle: 'Şarkı dosyalarını seç; aynı ad ve boyuttakiler '
                        'otomatik eşleşir',
                    accent: Colors.orangeAccent,
                    onTap: c.loading ? null : () => _relinkFlow(context),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- yardımcılar

  static void _snack(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  static String _err(Object e) =>
      e is BackupException ? e.message : 'Bir hata oluştu: $e';

  /// İlerleme penceresini açıb [task]-ı işlədir; bitəndə pəncərəni bağlayır.
  static Future<T> _withProgress<T>(
    BuildContext context,
    String title,
    Future<T> Function(ValueNotifier<_Prog> p) task,
  ) async {
    final p = ValueNotifier<_Prog>(const _Prog(-1, ''));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: ValueListenableBuilder<_Prog>(
            valueListenable: p,
            builder: (_, v, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: v.value < 0 ? null : v.value),
                const SizedBox(height: 12),
                Text(
                    v.value < 0
                        ? v.text
                        : '${v.text}  %${(v.value * 100).round()}',
                    style: TextStyle(color: kText60, fontSize: 13)),
                const SizedBox(height: 8),
                Text('Lütfen uygulamayı kapatma.',
                    style: TextStyle(color: kText54, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      return await task(p);
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  // ---------------------------------------------------------------- yedek oluştur

  static Future<void> _createFlow(BuildContext context) async {
    final c = PlayerController.instance;
    BackupPlan? plan;
    try {
      plan = await _withProgress<BackupPlan?>(context, 'Hazırlanıyor', (p) {
        p.value = const _Prog(-1, 'Boyut hesaplanıyor');
        return c.prepareBackup();
      });
    } catch (e) {
      _snack(context, _err(e));
      return;
    }
    if (!context.mounted) return;
    if (plan == null) {
      _snack(context, 'Kitaplık veritabanı okunamadı');
      return;
    }
    final BackupPlan pl = plan;
    if (pl.songCount == 0 && pl.playlistCount == 0) {
      _snack(context, 'Yedeklenecek bir şey yok: kitaplık boş');
      return;
    }

    final full = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yedek türünü seç'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '${pl.songCount} şarkı • ${pl.playlistCount} çalma listesi',
                  style: TextStyle(color: kText60, fontSize: 13)),
              const SizedBox(height: 12),
              _ModeCard(
                title: 'Tam yedek',
                size: '≈ ${formatBytes(pl.fullSize)}',
                text: 'Her şey + ${pl.audioCount} şarkı dosyası. '
                    'Geri yükleyince müzikler hazır gelir.',
                onTap: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: 10),
              _ModeCard(
                title: 'Hafif yedek',
                size: '≈ ${formatBytes(pl.lightSize)}',
                text: 'Şarkı dosyaları hariç, sadece bilgiler. Geri yükledikten '
                    'sonra şarkı dosyalarını yeniden seçersin; aynı ad ve '
                    'boyuttakiler otomatik eşleşir.',
                onTap: () => Navigator.of(ctx).pop(false),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('Vazgeç')),
        ],
      ),
    );
    if (full == null || !context.mounted) return;

    String path;
    int size;
    try {
      path = await _withProgress<String>(
        context,
        full ? 'Tam yedek alınıyor' : 'Hafif yedek alınıyor',
        (p) => c.createBackup(pl, full: full, onProgress: (v) {
          p.value = _Prog(v, 'Yedek dosyası yazılıyor');
        }),
      );
      size = await backupFileSize(path);
      BackupReminder.instance.markBackedUp(); // xatırlatma sayğacı sıfırlanır
    } catch (e) {
      _snack(context, _err(e));
      return;
    }
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yedek hazır'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Boyut: ${formatBytes(size)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(full ? 'Tam yedek' : 'Hafif yedek',
                style: TextStyle(color: kText60)),
            const SizedBox(height: 12),
            Text(
              'Şimdi "Kaydet / Paylaş" düğmesine bas ve "Dosyalar\'a Kaydet" '
              '(iCloud Drive) seç. Yedeğin orada olduğundan emin olmadan '
              'uygulamayı silme.',
              style: TextStyle(color: kText60, fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('Kapat')),
          Builder(
            builder: (btnCtx) => FilledButton.icon(
              onPressed: () => _share(btnCtx, path),
              icon: const Icon(Icons.ios_share),
              label: const Text('Kaydet / Paylaş'),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _share(BuildContext btnContext, String path) async {
    try {
      final box = btnContext.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path, mimeType: 'application/octet-stream')],
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
    } catch (e) {
      _snack(btnContext, 'Paylaşılamadı: $e');
    }
  }

  // ---------------------------------------------------------------- geri yükle

  static Future<void> _restoreFlow(BuildContext context) async {
    final c = PlayerController.instance;
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (picked.isEmpty || !context.mounted) return;
    final path = picked.first.path;
    if (path == null) {
      _snack(context, 'Dosya okunamadı');
      return;
    }

    BackupManifest manifest;
    try {
      manifest = await _withProgress<BackupManifest>(context, 'Yedek kontrol ediliyor',
          (p) => c.inspectBackup(path));
    } catch (e) {
      _snack(context, _err(e));
      return;
    }
    if (!context.mounted) return;

    final confirmed = await _confirmReplace(context, manifest, c);
    if (confirmed != true || !context.mounted) return;

    try {
      await _withProgress<void>(context, 'Geri yükleniyor', (p) {
        return c.restoreFromBackup(path, onProgress: (v, stage) {
          p.value = _Prog(v, stage);
        });
      });
    } catch (e) {
      _snack(context, _err(e));
      return;
    }
    // bərpa olunan yedəyin tarixi "son yedək" sayılır
    BackupReminder.instance.markBackedUp(atMs: manifest.createdMs);
    if (!context.mounted) return;

    final missing = c.missingAudioCount;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Geri yükleme tamamlandı'),
        content: Text(
          '${c.songs.length} şarkı ve ${c.playlists.length} çalma listesi geri yüklendi.'
          '${missing > 0 ? '\n\n$missing şarkının ses dosyası bu telefonda yok. '
              'Şimdi dosyaları seçersen aynı ad ve boyuttakiler otomatik eşleşir.' : ''}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(missing > 0 ? 'Sonra' : 'Tamam')),
          if (missing > 0)
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _relinkFlow(context);
              },
              child: const Text('Dosyaları seç'),
            ),
        ],
      ),
    );
  }

  /// Kitaplığı əvəz etməzdən əvvəl xəbərdarlıq. Mövcud kitaplıq boş deyilsə
  /// "Anladım" qutusunu işarələmədən düymə aktiv olmur.
  static Future<bool?> _confirmReplace(
      BuildContext context, BackupManifest m, PlayerController c) {
    final hasLibrary = c.songs.isNotEmpty || c.playlists.isNotEmpty;
    var understood = !hasLibrary;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded,
              color: Colors.redAccent, size: 36),
          title: const Text('Kitaplığın tamamen değiştirilecek'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasLibrary
                      ? 'Şu an kitaplığında ${c.songs.length} şarkı ve '
                          '${c.playlists.length} çalma listesi var. Geri yükleme '
                          'bunların HEPSİNİ siler: şarkılar, şarkı dosyaları, '
                          'listeler, beğeniler, istatistik, ayarlar. Bu geri alınamaz.'
                      : 'Geri yükleme, uygulamadaki her şeyi yedekteki ile değiştirir.',
                  style: const TextStyle(height: 1.4),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: kBg, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Yedek: ${m.full ? 'Tam' : 'Hafif'}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                          '${_date(m.created)}\n'
                          '${m.songCount} şarkı • ${m.playlistCount} çalma listesi'
                          '${m.full ? '\nŞarkı dosyaları: ${m.audioCount} (${formatBytes(m.audioBytes)})' : ''}',
                          style: TextStyle(color: kText70, fontSize: 13, height: 1.4)),
                    ],
                  ),
                ),
                if (!m.full) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Bu hafif bir yedek: şarkı dosyaları içermez. Geri yüklemeden '
                    'sonra şarkı dosyalarını yeniden seçmen gerekecek (şu an '
                    'telefondaki şarkı dosyaları da silinir).',
                    style: const TextStyle(
                        color: Colors.orangeAccent, fontSize: 13, height: 1.4),
                  ),
                ],
                if (hasLibrary) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: understood,
                    onChanged: (v) => setState(() => understood = v ?? false),
                    title: const Text('Anladım, mevcut kitaplık silinecek',
                        style: TextStyle(fontSize: 14)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Vazgeç')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: understood ? () => Navigator.of(ctx).pop(true) : null,
              child: const Text('Evet, değiştir'),
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  // ---------------------------------------------------------------- dosyaları bağla

  static Future<void> _relinkFlow(BuildContext context) async {
    final c = PlayerController.instance;
    final linked = await c.relinkMissingAudio();
    if (linked == null || !context.mounted) return;
    final left = c.missingAudioCount;
    _snack(
        context,
        linked == 0
            ? 'Eşleşen dosya bulunamadı (ad ve boyut aynı olmalı)'
            : '$linked şarkı bağlandı'
                '${left > 0 ? ', $left şarkının dosyası hâlâ eksik' : ''}');
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? accent;
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: accent ?? kGreen, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(color: kText60, fontSize: 12.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: kText38),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String size;
  final String text;
  final VoidCallback onTap;
  const _ModeCard({
    required this.title,
    required this.size,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  Text(size,
                      style: TextStyle(
                          color: kGreen, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 6),
              Text(text,
                  style: TextStyle(color: kText60, fontSize: 12.5, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}
