import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'backup_page.dart' show openBackupPage;
import 'main.dart' show kCard, kGreen, kText, kText54, kText60;
import 'persistence.dart';
import 'player_controller.dart';

/// TEST DÜYMƏSİ: true olanda xatırlatma web-də də görünür və gözləmə müddəti 0 gün sayılır.
/// Test bitəndə mütləq false yaz.
const bool kBackupReminderWebTest = false;

const _months = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// Yedək xatırlatması: son yedəyin vaxtını saxlayır və "çox keçib" olanda xəbərdarlıq göstərir.
class BackupReminder extends ChangeNotifier {
  BackupReminder._();
  static final BackupReminder instance = BackupReminder._();

  /// Seçimlər (həftə). 0 = xatırlatma söndürülüb.
  static const List<int> kWeekOptions = [2, 3, 4, 0];
  static const Duration kSnooze = Duration(days: 3);

  int lastBackupMs = 0; // 0 = heç yedək alınmayıb
  int snoozeUntilMs = 0;
  int weeks = 3;
  bool loaded = false;
  bool _loading = false;

  /// Baza açılandan sonra bir dəfə oxuyur. Təkrar çağırmaq təhlükəsizdir.
  Future<void> ensureLoaded() async {
    if (loaded || _loading) return;
    _loading = true;
    try {
      final m = await CloudioStore.instance.loadBackupInfo();
      if (m != null) {
        lastBackupMs = (m['last'] as num?)?.toInt() ?? 0;
        snoozeUntilMs = (m['snooze'] as num?)?.toInt() ?? 0;
        final w = (m['weeks'] as num?)?.toInt() ?? 3;
        weeks = kWeekOptions.contains(w) ? w : 3;
      }
      loaded = true;
    } finally {
      _loading = false;
    }
    notifyListeners();
  }

  void _save() {
    unawaited(
      CloudioStore.instance.saveBackupInfo(<String, Object?>{
        'last': lastBackupMs,
        'snooze': snoozeUntilMs,
        'weeks': weeks,
      }),
    );
  }

  /// Yedək faylı yaradılanda (və ya yedəkdən bərpa olunanda) çağırılır.
  void markBackedUp({int? atMs}) {
    lastBackupMs = atMs ?? DateTime.now().millisecondsSinceEpoch;
    snoozeUntilMs = 0;
    loaded = true;
    _save();
    notifyListeners();
  }

  void snooze() {
    snoozeUntilMs = DateTime.now().add(kSnooze).millisecondsSinceEpoch;
    _save();
    notifyListeners();
  }

  void setWeeks(int w) {
    if (!kWeekOptions.contains(w)) return;
    weeks = w;
    snoozeUntilMs = 0;
    _save();
    notifyListeners();
  }

  /// Son yedəkdən (yoxdursa hesabın yaradıldığı gündən) keçən gün.
  int daysSince(PlayerController c) {
    final ref = lastBackupMs > 0 ? lastBackupMs : c.profileSince.millisecondsSinceEpoch;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ref)).inDays;
  }

  bool shouldShow(PlayerController c) {
    if (!loaded || weeks <= 0) return false;
    if (!kBackupReminderWebTest && !c.backupSupported) return false;
    if (c.songs.isEmpty && c.playlists.isEmpty) return false;
    if (DateTime.now().millisecondsSinceEpoch < snoozeUntilMs) return false;
    return daysSince(c) >= (kBackupReminderWebTest ? 0 : weeks * 7);
  }
}

/// Ana sayfadakı xəbərdarlıq lövhəsi. Lazım olmayanda görünmür.
class BackupReminderBanner extends StatelessWidget {
  const BackupReminderBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    final r = BackupReminder.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([c, r]),
      builder: (context, _) {
        if (c.restored) unawaited(r.ensureLoaded());
        if (!r.shouldShow(c)) return const SizedBox.shrink();
        final days = r.daysSince(c);
        final title = r.lastBackupMs == 0
            ? 'Henüz hiç yedek almadın'
            : 'Son yedeğin $days gün önce alındı';
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Material(
            color: kCard,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.cloud_upload_outlined, color: Colors.orangeAccent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(
                              'Uygulamayı silersen kitaplığın ve ayarların kaybolur.',
                              style: TextStyle(color: kText60, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: r.snooze,
                        child: Text('Sonra', style: TextStyle(color: kText54)),
                      ),
                      TextButton(
                        onPressed: () => openBackupPage(context),
                        child: Text('Yedek al', style: TextStyle(color: kGreen)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Yedek səhifəsindəki kart: son yedək tarixi və xatırlatma sıxlığı.
class BackupReminderSettings extends StatelessWidget {
  const BackupReminderSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    final r = BackupReminder.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([c, r]),
      builder: (context, _) {
        if (c.restored) unawaited(r.ensureLoaded());
        String last;
        if (r.lastBackupMs == 0) {
          last = 'Son yedek: henüz alınmadı';
        } else {
          final d = DateTime.fromMillisecondsSinceEpoch(r.lastBackupMs);
          final days = r.daysSince(c);
          last =
              'Son yedek: ${d.day} ${_months[d.month - 1]} ${d.year} '
              '• ${days == 0 ? 'bugün' : '$days gün önce'}';
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(last, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text('Yedek hatırlatması', style: TextStyle(color: kText54, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final w in BackupReminder.kWeekOptions)
                    GestureDetector(
                      onTap: () => r.setWeeks(w),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: r.weeks == w ? kGreen : Colors.transparent,
                          border: Border.all(color: r.weeks == w ? kGreen : kText54),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          w == 0 ? 'Kapalı' : '$w hafta',
                          style: TextStyle(
                            color: r.weeks == w ? Colors.black : kText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                r.weeks == 0
                    ? 'Hatırlatma kapalı.'
                    : 'Yedek ${r.weeks} haftadır alınmadıysa ana sayfada uyarılır.',
                style: TextStyle(color: kText54, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
