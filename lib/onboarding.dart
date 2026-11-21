import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'main.dart' show kBg, kGreen, kText, kText38, kText54, kText60;
import 'persistence.dart';
import 'player_controller.dart';

/// TEST DÜYMƏSİ: true olanda qarşılama ekranı HƏR açılışda çıxır (kitabxana dolu olsa da).
/// Test bitəndə mütləq false yaz.
const bool kOnboardingForceShow = false;

/// Qarşılama ekranını əl ilə açır (Ayarlar → Hakkında). "Görüldü" qeydinə toxunmur.
void openOnboarding(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const OnboardingPage()));
}

bool _checkedThisRun = false;

/// Tətbiq açılanda çağırılır. Yalnız təzə (boş kitabxanalı) quraşdırmada ekranı göstərir.
Future<void> maybeShowOnboarding(BuildContext context) async {
  if (_checkedThisRun) return;
  _checkedThisRun = true;
  final c = PlayerController.instance;

  // kitabxananın diskdən yüklənməsini gözlə
  if (!c.restored) {
    final done = Completer<void>();
    void l() {
      if (c.restored && !done.isCompleted) done.complete();
    }

    c.addListener(l);
    await done.future;
    c.removeListener(l);
  }
  if (!context.mounted) return;

  if (!kOnboardingForceShow) {
    if (!CloudioStore.instance.enabled) return; // baza yoxdursa hər dəfə göstərməyək
    final seen = await CloudioStore.instance.loadOnboardingSeen();
    if (seen) return;
    // köhnə istifadəçi (kitabxanası dolu): səssizcə "görülüb" yaz
    if (c.songs.isNotEmpty || c.playlists.isNotEmpty) {
      await CloudioStore.instance.saveOnboardingSeen();
      return;
    }
    await CloudioStore.instance.saveOnboardingSeen();
  }
  if (!context.mounted) return;
  openOnboarding(context);
}

class _Slide {
  final IconData icon;
  final String title;
  final String body;
  const _Slide(this.icon, this.title, this.body);
}

const _slides = <_Slide>[
  _Slide(
    Icons.cloud_queue,
    'Cloudio\'ya hoş geldin',
    'Müziğin, kendi cihazında. Şarkılarını ekle, çalma listeleri oluştur ve '
        'sözlerle birlikte dinle.',
  ),
  _Slide(
    Icons.library_music_outlined,
    'Şarkılarını ekle',
    'Alttaki "Kitaplığın" sekmesini aç, sağ üstteki + düğmesine bas ve '
        'telefonundaki müzik dosyalarını seç (mp3, m4a, flac ve diğerleri). '
        'Kapak ve sözler internetten otomatik aranır.',
  ),
  _Slide(Icons.auto_awesome, 'Neler yapabilirsin', ''),
  _Slide(
    Icons.cloud_upload_outlined,
    'Yedek al',
    'Uygulamayı silersen kitaplığın da silinir. Ayarlar\'daki "Yedekle ve geri '
        'yükle" bölümünden düzenli yedek al ve Dosyalar\'a kaydet.',
  ),
];

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pc = PageController();
  final TextEditingController _name = TextEditingController();
  int _page = 0;

  bool get _last => _page == _slides.length - 1;

  @override
  void initState() {
    super.initState();
    final n = PlayerController.instance.profileName;
    if (n != 'Admin') _name.text = n;
  }

  @override
  void dispose() {
    _pc.dispose();
    _name.dispose();
    super.dispose();
  }

  void _next() {
    if (_last) {
      _finish(saveName: true);
    } else {
      _pc.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    }
  }

  void _finish({required bool saveName}) {
    if (saveName) {
      final c = PlayerController.instance;
      final n = _name.text.trim();
      if (n.isNotEmpty) c.setProfile(name: n, color: c.profileColor);
    }
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // iOS-da təsadüfən sola sürüşdürüb çıxmasın
      child: Scaffold(
        backgroundColor: kBg,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _last
                      ? const SizedBox.shrink()
                      : TextButton(
                          onPressed: () => _finish(saveName: false),
                          child: Text('Atla', style: TextStyle(color: kText54, fontSize: 15)),
                        ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pc,
                  itemCount: _slides.length,
                  onPageChanged: (i) {
                    FocusScope.of(context).unfocus();
                    setState(() => _page = i);
                  },
                  itemBuilder: (context, i) => _SlideView(
                    slide: _slides[i],
                    extra: i == 2
                        ? const _FeatureList()
                        : (i == _slides.length - 1 ? _nameField() : null),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? kGreen : kText38,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _next,
                    child: Text(
                      _last ? 'Başla' : 'Devam',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nameField() {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: TextField(
        controller: _name,
        maxLength: 20,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _finish(saveName: true),
        decoration: const InputDecoration(
          labelText: 'Adın ne? (isteğe bağlı)',
          hintText: 'Admin',
          counterText: '',
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  final Widget? extra;
  const _SlideView({required this.slide, this.extra});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kGreen.withValues(alpha: 0.15),
              ),
              child: Icon(slide.icon, size: 60, color: kGreen),
            ),
            const SizedBox(height: 32),
            Text(
              slide.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            if (slide.body.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                slide.body,
                textAlign: TextAlign.center,
                style: TextStyle(color: kText60, fontSize: 15, height: 1.5),
              ),
            ],
            ?extra,
          ],
        ),
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  const _FeatureList();

  static const _items = <(IconData, String, String)>[
    (Icons.lyrics, 'Senkron sözler', 'Çalan satır vurgulanır, dokununca oraya atlar'),
    (Icons.ios_share, 'Söz kartı', 'Beğendiğin dizeyi görsel yapıp paylaş'),
    (Icons.graphic_eq, 'Ses güçlendirici', '10x\'e kadar güçlendirme ve netlik'),
    (Icons.bedtime_outlined, 'Uyku zamanlayıcısı', 'Müzik belirlediğin zamanda durur'),
    (Icons.insights, 'Kişisel istatistik', 'En çok dinlediğin şarkı ve sanatçılar'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          for (final it in _items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Icon(it.$1, color: kGreen, size: 24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.$2,
                          style: TextStyle(color: kText, fontWeight: FontWeight.w600),
                        ),
                        Text(it.$3, style: TextStyle(color: kText60, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
