part of '../main.dart';

/// Now Playing fonu: kapağın dominant və ikinci rəngindən 3 dayanacaqlı gradient + yumşaq işıq halesi.
/// Kapaq dəyişəndə rənglər yumşaq keçidlə dəyişir. [rich] söndürülübsə köhnə sadə gradient.
class CoverBackground extends StatefulWidget {
  final Uint8List? cover;
  final Color fallback;
  final bool rich;
  final Widget child;
  const CoverBackground({
    super.key,
    required this.cover,
    required this.fallback,
    required this.rich,
    required this.child,
  });

  @override
  State<CoverBackground> createState() => _CoverBackgroundState();
}

class _CoverBackgroundState extends State<CoverBackground> {
  CoverPalette? _pal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CoverBackground old) {
    super.didUpdateWidget(old);
    if (!identical(old.cover, widget.cover)) _load();
  }

  void _load() {
    final cv = widget.cover;
    if (cv == null) {
      _pal = null;
      return;
    }
    coverPalette(cv).then((p) {
      if (!mounted || !identical(widget.cover, cv)) return;
      setState(() => _pal = p);
    });
  }

  /// Fon üçün rəngi tündləşdirir; boz kapaqda doyğunluğu süni artırmır.
  static Color _shade(Color c, double light) {
    final h = HSLColor.fromColor(c);
    final sat = h.saturation < 0.12 ? h.saturation : h.saturation.clamp(0.35, 0.85);
    return h.withLightness(light).withSaturation(sat.toDouble()).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.rich && widget.cover != null ? _pal : null;
    const dur = Duration(milliseconds: 700);
    if (p == null) {
      return AnimatedContainer(
        duration: dur,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [widget.fallback, kBg],
            stops: const [0.0, 0.7],
          ),
        ),
        child: widget.child,
      );
    }
    final top = _shade(p.primary, 0.30);
    final mid = _shade(p.secondary, 0.16);
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedContainer(
            duration: dur,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, mid, kBg],
                stops: const [0.0, 0.45, 0.85],
              ),
            ),
          ),
        ),
        // kapağın arxasında yumşaq işıq halesi
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: dur,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 0.85,
                  colors: [
                    _shade(p.primary, 0.45).withValues(alpha: 0.38),
                    _shade(p.primary, 0.45).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}
