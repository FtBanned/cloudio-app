import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'main.dart' show kGreen;
import 'wizard_mascot.dart';

/// Rehberin işıq salacağı real interfeys elementləri. app_shell.dart bu açarları
/// alt menü düymələrinə və mini oynadıcıya bağlayır.
class TourKeys {
  static final home = GlobalKey(debugLabel: 'tour-home');
  static final search = GlobalKey(debugLabel: 'tour-search');
  static final library = GlobalKey(debugLabel: 'tour-library');
  static final create = GlobalKey(debugLabel: 'tour-create');
  static final miniPlayer = GlobalKey(debugLabel: 'tour-mini-player');

  // Mərhələ 1: səhifələrin içindəki elementlər
  static final homeAvatar = GlobalKey(debugLabel: 'tour-home-avatar');
  static final homeFilters = GlobalKey(debugLabel: 'tour-home-filters');
  static final searchField = GlobalKey(debugLabel: 'tour-search-field');
  static final libraryAdd = GlobalKey(debugLabel: 'tour-library-add');
  static final libLiked = GlobalKey(debugLabel: 'tour-lib-liked');
  static final libAll = GlobalKey(debugLabel: 'tour-lib-all');
  static final createPanel = GlobalKey(debugLabel: 'tour-create-panel');
}

/// Rehberin tətbiqi "idarə etməsi" üçün körpü. MainShell özünü bura qeyd edir,
/// rehber isə tab dəyişir / "Oluştur" pəncərəsini açıb-bağlayır.
class TourBridge {
  static void Function(int tab)? selectTab;
  static void Function(bool open)? setCreateOpen;
}

/// Animasiyalı rehberi idarə edir. Rehber MaterialApp-ın `builder`-ində qurulmuş
/// [GuidedTourHost] vasitəsilə bütün ekranların üstündə göstərilir.
class GuidedTour {
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// Rehberi başladır. [delay]: açılan səhifənin bağlanma animasiyasını gözləmək üçün.
  static void start({Duration delay = Duration.zero}) {
    if (delay == Duration.zero) {
      active.value = true;
    } else {
      Future<void>.delayed(delay, () => active.value = true);
    }
  }

  static void stop() {
    active.value = false;
    TourBridge.setCreateOpen?.call(false);
  }
}

class GuidedTourHost extends StatelessWidget {
  const GuidedTourHost({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GuidedTour.active,
      builder: (context, on, _) =>
          on ? const Positioned.fill(child: _TourOverlay()) : const SizedBox.shrink(),
    );
  }
}

class _TourStep {
  final GlobalKey? target;
  final String title;
  final String body;
  final WizardMood mood;

  /// true: hədəfin üstündə "toxun" animasiyası (əl + dalğa) göstərilir
  final bool tap;

  /// null deyilsə: kartda bir-bir yanan özəllik ikonları göstərilir
  final List<(IconData, String)>? features;

  /// Addım açılan kimi dərhal işləyir (tab seç, pəncərə aç/bağla). Təkrar çağırıla bilər.
  final VoidCallback? prepare;

  /// "Toxun" animasiyasından bir az sonra rehberin ÖZÜ yerinə yetirdiyi hərəkət.
  final VoidCallback? act;

  const _TourStep({
    this.target,
    required this.title,
    required this.body,
    this.mood = WizardMood.idle,
    this.tap = false,
    this.features,
    this.prepare,
    this.act,
  });
}

void _tab(int i) => TourBridge.selectTab?.call(i);
void _create(bool open) => TourBridge.setCreateOpen?.call(open);

final List<_TourStep> _steps = [
  _TourStep(
    title: 'Merhaba, ben Cloudio Büyücüsü!',
    body: 'Sana uygulamayı gezdireyim. Düğmelere ben basacağım, sen sadece izle. Hazırsan başlayalım!',
    mood: WizardMood.wave,
    prepare: () {
      _create(false);
      _tab(0);
    },
  ),
  // ---------- Mərhələ 1: əsas sekmələr ----------
  _TourStep(
    target: TourKeys.home,
    tap: true,
    title: 'Ana sayfa',
    body: 'Son çaldıkların, en çok dinlediklerin ve geçen yıl bugün ne dinlediğin burada.',
    prepare: () => _create(false),
    act: () => _tab(0),
  ),
  _TourStep(
    target: TourKeys.homeAvatar,
    title: 'Profil ve ayarlar',
    body: 'Profil resmine dokunursan Ayarlar açılır: tema, yedekleme ve çalma ayarları orada.',
    prepare: () => _tab(0),
  ),
  _TourStep(
    target: TourKeys.homeFilters,
    title: 'Tümü / Müzik',
    body: '"Tümü" özet rafları gösterir. "Müzik"e basarsan bütün şarkıların alt alta listelenir.',
    prepare: () => _tab(0),
  ),
  _TourStep(
    target: TourKeys.search,
    tap: true,
    title: 'Arama sekmesi',
    body: 'Şarkı, sanatçı veya albüm adını yaz, hemen bulayım.',
    prepare: () => _create(false),
    act: () => _tab(1),
  ),
  _TourStep(
    target: TourKeys.searchField,
    title: 'Arama kutusu',
    body: 'Buraya yazdıkça sonuçlar canlı çıkar. Boşken türlere göre göz atabilirsin.',
    prepare: () => _tab(1),
  ),
  _TourStep(
    target: TourKeys.library,
    tap: true,
    title: 'Kitaplığın sekmesi',
    body: 'Bütün müziğin, beğendiklerin ve çalma listelerin burada durur.',
    prepare: () => _create(false),
    act: () => _tab(2),
  ),
  _TourStep(
    target: TourKeys.libraryAdd,
    tap: true,
    title: 'Şarkı ekle',
    body:
        'Sağ üstteki + ile telefonundaki müzik dosyalarını seçersin. '
        'Kapak ve sözleri internetten ben bulurum.',
    prepare: () => _tab(2),
  ),
  _TourStep(
    target: TourKeys.libLiked,
    title: 'Beğenilen Şarkılar',
    body: 'Şarkı ekranında ✓ düğmesine bastığın bütün şarkılar bu listede toplanır.',
    prepare: () => _tab(2),
  ),
  _TourStep(
    target: TourKeys.libAll,
    title: 'Tüm Şarkılar',
    body: 'Eklediğin bütün şarkılar burada. Birine dokunursan hemen çalmaya başlar.',
    prepare: () => _tab(2),
  ),
  _TourStep(
    target: TourKeys.create,
    tap: true,
    title: 'Çalma listesi oluştur',
    body: 'Buna basınca küçük bir pencere açılır. Hadi birlikte bakalım!',
    prepare: () => _create(false),
    act: () => _create(true),
  ),
  _TourStep(
    target: TourKeys.createPanel,
    title: 'Yeni çalma listesi',
    body: 'Buna basıp listeye bir ad verirsin. Şarkıları şarkı menüsünden (⋯) içine eklersin.',
    prepare: () => _create(true),
  ),
  // ---------- Mərhələ 2+ üçün müvəqqəti: köhnə addımlar ----------
  _TourStep(
    target: TourKeys.miniPlayer,
    title: 'Mini oynatıcı',
    body:
        'Bir şarkı çalarken altta mini oynatıcı belirir. Ona dokunursan tam ekran açılır: '
        'sözler, sıra, hız ve daha fazlası.',
    prepare: () => _create(false),
  ),
  const _TourStep(
    title: 'Sihirli özellikler',
    body: 'Tam ekran oynatıcıda bunların hepsi var. Hepsini bir kez dene!',
    mood: WizardMood.cheer,
    features: [
      (Icons.lyrics, 'Sözler'),
      (Icons.ios_share, 'Söz kartı'),
      (Icons.graphic_eq, 'Güçlendirici'),
      (Icons.bedtime_outlined, 'Uyku'),
    ],
  ),
  const _TourStep(
    title: 'Yedeklemeyi unutma',
    body:
        'Uygulamayı silersen kitaplığın da gider. Ayarlar → "Yedekle ve geri yükle" ile '
        'düzenli yedek al.',
  ),
  _TourStep(
    title: 'Hazırsın!',
    body: 'Beni tekrar görmek istersen Ayarlar → Hakkında → "Büyücü rehberi"ne bas. İyi dinlemeler!',
    mood: WizardMood.cheer,
    prepare: () {
      _create(false);
      _tab(0);
    },
  ),
];

class _TourOverlay extends StatefulWidget {
  const _TourOverlay();

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> with SingleTickerProviderStateMixin {
  // 6 saniyəlik dövr: ripple (2 san), özəllik ikonları (1.5 san) bundan türəyir
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  int _i = 0;
  int _chars = 0;
  Timer? _typer;
  Timer? _actTimer;

  _TourStep get _step => _steps[_i];
  bool get _typing => _chars < _step.body.length;

  @override
  void initState() {
    super.initState();
    // prepare ilk kadrdan sonra çağırılır (build zamanı setState olmasın)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enter();
    });
  }

  @override
  void dispose() {
    _typer?.cancel();
    _actTimer?.cancel();
    _loop.dispose();
    super.dispose();
  }

  /// Yeni addıma girəndə: vəziyyəti hazırla, yazmağa başla, lazımdırsa 1 san sonra özü toxun.
  void _enter() {
    _actTimer?.cancel();
    final s = _step;
    s.prepare?.call();
    _startTyping();
    if (s.act != null) {
      _actTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted && identical(_step, s)) s.act!();
      });
    }
  }

  void _startTyping() {
    _typer?.cancel();
    _chars = 0;
    final len = _step.body.length;
    _typer = Timer.periodic(const Duration(milliseconds: 22), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_chars >= len) {
        t.cancel();
        return;
      }
      setState(() => _chars++);
    });
  }

  void _skipTyping() {
    if (!_typing) return;
    _typer?.cancel();
    setState(() => _chars = _step.body.length);
  }

  void _go(int delta) {
    final n = _i + delta;
    if (n < 0) return;
    if (n >= _steps.length) {
      GuidedTour.stop();
      return;
    }
    setState(() => _i = n);
    _enter();
  }

  /// Hədəf elementin ekrandakı düzbucağı (görünmürsə / ölçüsü yoxdursa null).
  Rect? _rectOf(GlobalKey? key) {
    final ro = key?.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    return (r.width < 8 || r.height < 8) ? null : r;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final step = _step;
    final target = _rectOf(step.target);
    // hədəf yoxdursa: mərkəzdə sıfır ölçülü "çuxur" (hər şey qaralır)
    final hole = target != null
        ? target.inflate(6)
        : Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);
    final lower = target != null && target.center.dy > size.height * 0.5;
    final align = target == null
        ? const Alignment(0, 0)
        : (lower ? const Alignment(0, -1) : const Alignment(0, 1));
    final mood = _typing ? WizardMood.talk : step.mood;
    final last = _i == _steps.length - 1;

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _loop,
        builder: (context, _) {
          final ripple = (_loop.value * 3) % 1.0;
          return Stack(
            children: [
              // qaranlıq pərdə + hədəf ətrafında parlayan çərçivə; toxunuşları udur
              Positioned.fill(
                key: const ValueKey('tour-scrim'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _skipTyping,
                  child: TweenAnimationBuilder<Rect?>(
                    tween: RectTween(end: hole),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOutCubic,
                    builder: (context, r, _) => CustomPaint(
                      painter: _ScrimPainter(r ?? hole, ripple),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
              // "toxun" göstəricisi
              if (target != null && step.tap)
                Positioned(
                  key: const ValueKey('tour-hint'),
                  left: target.center.dx - 40,
                  top: target.center.dy - 40,
                  width: 80,
                  height: 80,
                  child: IgnorePointer(child: _TapHint(ripple)),
                ),
              // büyücü + danışma qutusu
              Padding(
                key: const ValueKey('tour-card'),
                padding: EdgeInsets.fromLTRB(
                  18,
                  mq.padding.top + 120,
                  18,
                  mq.padding.bottom + 28,
                ),
                child: Align(alignment: align, child: _card(mood, last)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(WizardMood mood, bool last) {
    final step = _step;
    const white = Color(0xFFF4F1FF);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF241E4A),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: kGreen.withValues(alpha: 0.65), width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 70), // büyücüyə yer
                child: Text(
                  step.title,
                  style: const TextStyle(
                    color: white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // görünməz tam mətn: yazılma zamanı kart hündürlüyü tullanmasın
              Stack(
                children: [
                  Opacity(opacity: 0, child: Text(step.body, style: _bodyStyle)),
                  Text(step.body.substring(0, _chars), style: _bodyStyle),
                ],
              ),
              if (step.features != null) ...[const SizedBox(height: 14), _featureRow(step.features!)],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var j = 0; j < _steps.length; j++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: j == _i ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: j == _i ? kGreen : Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (!last)
                    TextButton(
                      onPressed: GuidedTour.stop,
                      child: const Text('Atla', style: TextStyle(color: Colors.white54)),
                    ),
                  const Spacer(),
                  if (_i > 0)
                    TextButton(
                      onPressed: () => _go(-1),
                      child: const Text('Geri', style: TextStyle(color: Colors.white70)),
                    ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: () => _go(1),
                    child: Text(
                      last ? 'Başla' : (_i == 0 ? 'Hadi!' : 'Devam'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // büyücü kartın yuxarı sağ küncündə oturur
        Positioned(
          right: 14,
          top: -98,
          child: IgnorePointer(child: WizardMascot(height: 112, mood: mood)),
        ),
      ],
    );
  }

  static const _bodyStyle = TextStyle(
    color: Color(0xFFD9D4F2),
    fontSize: 14.5,
    height: 1.45,
    decoration: TextDecoration.none,
    fontWeight: FontWeight.normal,
  );

  /// Dörd özəllik ikonu növbə ilə böyüyüb parlayır (6 san dövrünün dörddə biri).
  Widget _featureRow(List<(IconData, String)> items) {
    final active = (_loop.value * items.length).floor().clamp(0, items.length - 1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var j = 0; j < items.length; j++)
          AnimatedScale(
            scale: j == active ? 1.18 : 1.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: j == active ? kGreen.withValues(alpha: 0.28) : Colors.white10,
                    border: Border.all(color: j == active ? kGreen : Colors.transparent, width: 1.5),
                  ),
                  child: Icon(items[j].$1, color: j == active ? kGreen : Colors.white60),
                ),
                const SizedBox(height: 4),
                Text(
                  items[j].$2,
                  style: TextStyle(
                    color: j == active ? Colors.white : Colors.white54,
                    fontSize: 11,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Qaranlıq pərdə: hədəf düzbucağı boş qalır, ətrafında vurğu rəngli çərçivə + yayılan halqa.
class _ScrimPainter extends CustomPainter {
  final Rect hole;
  final double pulse; // 0..1
  _ScrimPainter(this.hole, this.pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()..addRect(Offset.zero & size);
    final hasHole = hole.width > 2 && hole.height > 2;
    final rr = RRect.fromRectAndRadius(hole, const Radius.circular(16));
    if (hasHole) {
      scrim
        ..addRRect(rr)
        ..fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(scrim, Paint()..color = const Color(0xCC0B0820));
    if (!hasHole) return;
    canvas.drawRRect(
      rr.inflate(pulse * 10),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kGreen.withValues(alpha: (1 - pulse) * 0.55),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = kGreen,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole || old.pulse != pulse;
}

/// Hədəfin üstündə: yayılan halqa + basılıb qalxan əl işarəsi.
class _TapHint extends StatelessWidget {
  final double t; // 0..1
  const _TapHint(this.t);

  @override
  Widget build(BuildContext context) {
    final press = math.sin(math.pi * (t * 2).clamp(0.0, 1.0)); // 0→1→0 ilk yarıda
    return CustomPaint(
      painter: _RipplePainter(t),
      child: Transform.translate(
        offset: Offset(10, 12 + press * 6),
        child: Transform.scale(
          scale: 1 - 0.12 * press,
          // barmaq ucu: ikon əvəzinə çəkilmiş dairə (yeni ikon = font dəyişir = Shorebird patch rədd edir)
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.92),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double t;
  _RipplePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final k = Curves.easeOut.transform(t);
    canvas.drawCircle(
      c,
      8 + k * 30,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: (1 - k) * 0.8),
    );
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.t != t;
}
