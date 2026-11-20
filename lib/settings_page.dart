import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'app_theme.dart';
import 'main.dart'
    show
        kBg,
        kCard,
        kGreen,
        kText,
        kText38,
        kText54,
        kText60,
        kText70,
        formatTotal,
        showSleepSheet;
import 'player_controller.dart';
import 'stats_page.dart';

/// Ayarlar səhifəsini açır (profil şəkli və Now Playing-dəki "tune" düyməsi bunu çağırır).
void openSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
  );
}

String crossfadeLabel(double v) {
  if (v <= 0) return 'Kapalı';
  if (v < 1) return 'Boşluksuz';
  return '${v.round()} sn';
}

String speedLabel(double v) {
  final t = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  return '${t}x';
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _crossfadeOptions = <double>[0, 0.25, 3, 5, 8, 12];

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) => ListView(
          padding: EdgeInsets.only(
              bottom: 24 + MediaQuery.of(context).padding.bottom),
          children: [
            // ---------- Hesap ----------
            const _ProfileCard(),

            ListTile(
              leading: Icon(Icons.insights_outlined, color: kGreen),
              title: const Text('Kişisel istatistik'),
              subtitle: Text(
                  'Aylık sanatçılar, dinleme süresi, en çok dinlenenler',
                  style: TextStyle(color: kText54, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: kText38),
              onTap: () => openStats(context),
            ),

            // ---------- Çalma ----------
            const _SectionTitle('Çalma'),
            _Block(
              title: 'Çalma hızı',
              trailing: speedLabel(c.speed),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in PlayerController.speedOptions)
                    _Chip(
                      label: speedLabel(v),
                      selected: c.speed == v,
                      onTap: () => c.setSpeed(v),
                    ),
                ],
              ),
            ),
            if (c.crossfadeSupported)
              _Block(
                title: 'Şarkılar arası geçiş',
                trailing: crossfadeLabel(c.crossfadeSecs),
                note:
                    'Sıradaki şarkı otomatik geçişte önceden hazırlanır. '
                    'Tek şarkı tekrarında ve uyku zamanlayıcısı "şarkı bitince" iken uygulanmaz.',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in _crossfadeOptions)
                      _Chip(
                        label: crossfadeLabel(o),
                        selected: c.crossfadeSecs == o,
                        onTap: () => c.setCrossfade(o),
                      ),
                  ],
                ),
              ),
            SwitchListTile(
              activeThumbColor: kGreen,
              title: const Text('Ses seviyesini dengele'),
              subtitle: Text(
                  'Şarkılar arası ses farkını azaltır (ReplayGain etiketine göre). '
                  '${c.gainTaggedCount}/${c.songs.length} şarkıda etiket var.',
                  style: TextStyle(color: kText54, fontSize: 12)),
              value: c.normalizeOn,
              onChanged: c.setNormalize,
            ),

            // ---------- Görünüş ----------
            const _SectionTitle('Görünüş'),
            const _ThemeBlock(),
            SwitchListTile(
              activeThumbColor: kGreen,
              title: const Text('Dinamik arka plan'),
              subtitle: Text(
                  'Çalıyor ekranının arka planı albüm kapağının renklerinden oluşur.',
                  style: TextStyle(color: kText54, fontSize: 12)),
              value: c.dynamicBg,
              onChanged: c.setDynamicBg,
            ),

            // ---------- Uyku zamanlayıcısı ----------
            const _SectionTitle('Uyku zamanlayıcısı'),
            ListTile(
              leading: Icon(Icons.bedtime_outlined,
                  color: c.sleepActive ? kGreen : kText70),
              title: const Text('Müziği otomatik durdur'),
              subtitle: Text(_sleepStatus(c),
                  style: TextStyle(
                      color: c.sleepActive ? kGreen : kText54,
                      fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: kText38),
              onTap: () => showSleepSheet(context),
            ),

            // ---------- Kitaplık ----------
            const _SectionTitle('Kitaplık'),
            ListTile(
              leading: Icon(Icons.library_music_outlined,
                  color: kText70),
              title: Text('${c.songs.length} şarkı'),
              subtitle: Text(
                  formatTotal(c.songs).isEmpty
                      ? 'Toplam süre henüz bilinmiyor'
                      : 'Toplam süre: ${formatTotal(c.songs)}',
                  style: TextStyle(color: kText54, fontSize: 12)),
            ),

            // ---------- Hakkında ----------
            const _SectionTitle('Hakkında'),
            ListTile(
              leading: Icon(Icons.info_outline, color: kText70),
              title: Text('Cloudio'),
              subtitle: Text('Sürüm 1.0.0',
                  style: TextStyle(color: kText54, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  static String _sleepStatus(PlayerController c) {
    if (c.sleepAtSongEnd) return 'Şarkı bitince duracak';
    final end = c.sleepEndsAt;
    if (end != null) {
      final left = end.difference(DateTime.now());
      final m = left.inMinutes + (left.inSeconds % 60 > 0 ? 1 : 0);
      final hh = end.hour.toString().padLeft(2, '0');
      final mm = end.minute.toString().padLeft(2, '0');
      return 'Duracağı saat: $hh:$mm (~${m < 1 ? 1 : m} dk kaldı)';
    }
    return 'Kapalı';
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: kText54,
              letterSpacing: 0.5)),
    );
  }
}

/// Başlıq + cari dəyər + seçim düymələri + izah mətni.
class _Block extends StatelessWidget {
  final String title;
  final String trailing;
  final String? note;
  final Widget child;
  const _Block({
    required this.title,
    required this.trailing,
    required this.child,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 16)),
              ),
              Text(trailing,
                  style: TextStyle(
                      color: kGreen, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          child,
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note!,
                style: TextStyle(color: kText54, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

/// Tema rejimi (Tünd / AMOLED / Açıq) və vurğu rəngi seçimi.
class _ThemeBlock extends StatelessWidget {
  const _ThemeBlock();

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.instance;
    return Column(
      children: [
        _Block(
          title: 'Tema',
          trailing: themeModeLabel(t.mode),
          note: 'AMOLED: tam siyah arka plan, OLED ekranlarda pil tasarrufu sağlar.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in AppThemeMode.values)
                _Chip(
                  label: themeModeLabel(m),
                  selected: t.mode == m,
                  onTap: () => t.set(mode: m),
                ),
            ],
          ),
        ),
        _Block(
          title: 'Vurgu rengi',
          trailing: kAccentColors[t.accentIndex].$1,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < kAccentColors.length; i++)
                GestureDetector(
                  onTap: () => t.set(accentIndex: i),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: kAccentColors[i].$2,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: t.accentIndex == i
                              ? kText
                              : Colors.transparent,
                          width: 2.5),
                    ),
                    child: t.accentIndex == i
                        ? const Icon(Icons.check, size: 20, color: Colors.black)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kGreen : kCard,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.black : kText,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}


// ================= Hesap / profil =================

/// Profil rəngləri: (açıq, tünd). Avatar və kart gradienti bunlardan qurulur.
const kProfileColors = <(Color, Color)>[
  (Color(0xFF1DB954), Color(0xFF0B5D2A)), // yaşıl
  (Color(0xFF7C4DFF), Color(0xFF2A1670)), // bənövşəyi
  (Color(0xFFFF6D3A), Color(0xFF7A2A0C)), // narıncı
  (Color(0xFF29B6F6), Color(0xFF0B4A70)), // mavi
  (Color(0xFFEC407A), Color(0xFF731836)), // çəhrayı
  (Color(0xFFFFCA28), Color(0xFF6B4E00)), // sarı
];

(Color, Color) _pal(int i) => kProfileColors[i.clamp(0, kProfileColors.length - 1)];

String _initial(String name) {
  final t = name.trim();
  return t.isEmpty ? 'A' : t.characters.first.toUpperCase();
}

String _hm(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '$h sa $m dk';
  if (d.inMinutes > 0) return '${d.inMinutes} dk';
  return '0 dk';
}

const _months = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
];

/// Gradient halqalı dairəvi avatar: hərf = adın ilk hərfi.
class ProfileCircle extends StatelessWidget {
  final double radius;
  const ProfileCircle({super.key, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final (light, dark) = _pal(c.profileColor);
        return Container(
          padding: EdgeInsets.all(radius > 24 ? 3 : 1.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, light],
            ),
          ),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: dark,
            // Admin hesabı: hərf əvəzinə assets/admin_bg.jpg fotosu.
            // Foto tapılmasa köhnə kimi adın ilk hərfi göstərilir.
            child: ClipOval(
              child: Image.asset(
                'assets/admin_bg.jpg',
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                // 1920x1080 şəkli tam ölçüdə yaddaşa yükləməsin
                cacheWidth: (radius * 2 * 4).round(),
                errorBuilder: (_, __, ___) => Center(
                  child: Text(_initial(c.profileName),
                      style: TextStyle(
                          fontSize: radius * 0.95,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    final (light, dark) = _pal(c.profileColor);
    final top = c.topArtist;
    final since = c.profileSince;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: light.withValues(alpha: 0.20),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: light.withValues(alpha: 0.35)),
      ),
      child: Stack(
        children: [
          // Foto + animasiyalı video fon (üstündə profil rənginə uyğun tünd qat)
          Positioned.fill(child: _AdminBackdrop(tint: dark)),
          Padding(
            padding: const EdgeInsets.all(18),
            child: DarkZone(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ProfileCircle(radius: 34),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.profileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const _AdminBadge(),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Profili düzenle',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editProfile(context),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _Stat(value: '${c.songs.length}', label: 'Şarkı'),
              _Stat(value: '${c.totalPlays}', label: 'Dinleme'),
              _Stat(value: _hm(c.listenedTime), label: 'Süre'),
            ],
          ),
          if (top != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.local_fire_department, size: 18, color: light),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('En çok dinlenen: ${top.$1} (${top.$2} kez)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: light, padding: EdgeInsets.zero),
              onPressed: () => openStats(context),
              icon: const Icon(Icons.insights_outlined, size: 18),
              label: const Text('Kişisel istatistik'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
              'Bu cihazdaki yerel hesap • ${_months[since.month - 1]} ${since.year}'
              ' tarihinden beri',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
            ),
          ),
        ],
      ),
    );
  }

  void _editProfile(BuildContext context) {
    final c = PlayerController.instance;
    final ctl = TextEditingController(text: c.profileName);
    var color = c.profileColor;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Profili düzenle',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: ctl,
                  maxLength: 20,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Ad'),
                ),
                const SizedBox(height: 8),
                Text('Renk',
                    style: TextStyle(
                        color: kText70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < kProfileColors.length; i++)
                      GestureDetector(
                        onTap: () => setS(() => color = i),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [kProfileColors[i].$1, kProfileColors[i].$2],
                            ),
                            border: Border.all(
                                color: color == i
                                    ? kText
                                    : Colors.transparent,
                                width: 2.5),
                          ),
                          child: color == i
                              ? const Icon(Icons.check,
                                  size: 20, color: Colors.white)
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: kGreen, foregroundColor: Colors.black),
                    onPressed: () {
                      c.setProfile(name: ctl.text, color: color);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Kaydet'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Admin kartının fonu: önce foto görünür, video hazır olunca sessiz ve döngüyle oynar.
/// Video açılmazsa (hata) foto kalır, uygulama çalışmaya devam eder.
///
/// Pil ve ısı tasarrufu: kartın üstünü başka bir sayfa kapatınca (ör. istatistik
/// sayfası) ya da uygulama arka plana/kilit ekranına geçince video duraklatılır,
/// kart yeniden görününce kaldığı yerden devam eder.
class _AdminBackdrop extends StatefulWidget {
  final Color tint;
  const _AdminBackdrop({required this.tint});

  @override
  State<_AdminBackdrop> createState() => _AdminBackdropState();
}

class _AdminBackdropState extends State<_AdminBackdrop>
    with WidgetsBindingObserver {
  VideoPlayerController? _vc;
  bool _ready = false;
  bool _gone = false;
  bool _pageVisible = true; // üstünü başka sayfa kapatmadı mı
  bool _appForeground = true; // uygulama ön planda mı

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      // ÖNEMLİ: videoPlayerOptions(mixWithOthers: true) VERMİYORUZ. iOS'ta bu seçenek
      // uygulamanın ortak ses oturumunu "diğer seslerle karışır" moduna alıyor; iOS de
      // bu modda kilit ekranı / Control Center müzik kontrollerini göstermiyor (bir süre
      // sonra kayboluyordu). Video zaten sessiz ve içinde ses kanalı yok, müziği kesmez.
      final vc = VideoPlayerController.asset('assets/admin_bg.mp4');
      _vc = vc;
      await vc.initialize();
      await _restoreMusicSession();
      if (_gone) return; // dispose() controller'ı zaten kapattı
      await vc.setVolume(0);
      await vc.setLooping(true);
      if (_gone) return;
      setState(() => _ready = true);
      _syncPlayback();
    } catch (e) {
      debugPrint('Admin fon videosu açılmadı: $e');
    }
  }

  /// Video eklentisi ses oturumunun kategorisini değiştirmiş olabilir; müzik çalar için
  /// gereken (karışmayan, "playback") ayarı geri yükler. Oturumu etkinleştirmez,
  /// yani başka uygulamanın sesini kesmez.
  Future<void> _restoreMusicSession() async {
    if (kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      debugPrint('Ses oturumu geri yüklenemedi: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Başka bir sayfa bu sayfanın üstünü kapatınca TickerMode kapanır.
    _pageVisible = TickerMode.of(context);
    _syncPlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appForeground = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  /// Video yalnızca kart görünürken ve uygulama ön plandayken oynar.
  void _syncPlayback() {
    final vc = _vc;
    if (vc == null || !_ready || _gone) return;
    final shouldPlay = _pageVisible && _appForeground;
    if (shouldPlay && !vc.value.isPlaying) {
      vc.play();
    } else if (!shouldPlay && vc.value.isPlaying) {
      vc.pause();
    }
  }

  @override
  void dispose() {
    _gone = true;
    WidgetsBinding.instance.removeObserver(this);
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vc = _vc;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/admin_bg.jpg', fit: BoxFit.cover),
        if (_ready && vc != null)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: vc.value.size.width,
              height: vc.value.size.height,
              child: VideoPlayer(vc),
            ),
          ),
        // Yazıların okunması için koyu katman (profil rengiyle)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                widget.tint.withValues(alpha: 0.35),
                const Color(0xFF121212).withValues(alpha: 0.85),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminBadge extends StatelessWidget {
  const _AdminBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
            colors: [Color(0xFFFFE082), Color(0xFFFFB300)]),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, size: 15, color: Color(0xFF4A3300)),
          SizedBox(width: 4),
          Text('ADMIN',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: Color(0xFF4A3300))),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: kText54, fontSize: 12)),
        ],
      ),
    );
  }
}
