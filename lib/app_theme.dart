import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import 'persistence.dart';

/// Tünd (standart), AMOLED (tam qara) və Açıq tema.
enum AppThemeMode { dark, amoled, light }

/// Vurğu rəngləri (düymələr, seçilmiş elementlər, tikələr).
const kAccentColors = <(String, Color)>[
  ('Yeşil', Color(0xFF1DB954)),
  ('Mavi', Color(0xFF2E9BFF)),
  ('Mor', Color(0xFF9B6BFF)),
  ('Pembe', Color(0xFFF0508C)),
  ('Turuncu', Color(0xFFFF7A3D)),
  ('Sarı', Color(0xFFFFC933)),
  ('Kırmızı', Color(0xFFEF4444)),
  ('Turkuaz', Color(0xFF14B8A6)),
];

String themeModeLabel(AppThemeMode m) => switch (m) {
      AppThemeMode.dark => 'Koyu',
      AppThemeMode.amoled => 'AMOLED',
      AppThemeMode.light => 'Açık',
    };

/// Tətbiqin cari görünüşü. Rənglər (kGreen, kBg, kCard, kText...) buradan oxunur.
class AppTheme extends ChangeNotifier {
  AppTheme._();
  static final AppTheme instance = AppTheme._();

  AppThemeMode mode = AppThemeMode.dark;
  int accentIndex = 0;

  bool get isLight => mode == AppThemeMode.light;
  Brightness get brightness => isLight ? Brightness.light : Brightness.dark;

  Color get accent => kAccentColors[accentIndex.clamp(0, kAccentColors.length - 1)].$2;

  Color get bg => switch (mode) {
        AppThemeMode.dark => const Color(0xFF121212),
        AppThemeMode.amoled => const Color(0xFF000000),
        AppThemeMode.light => const Color(0xFFF6F6F6),
      };

  Color get card => switch (mode) {
        AppThemeMode.dark => const Color(0xFF2A2A2A),
        AppThemeMode.amoled => const Color(0xFF1A1A1A),
        AppThemeMode.light => const Color(0xFFE4E4E4),
      };

  /// Yazı / ikon rəngi: tündə ağ, açıqda qara. [alpha] 0..255.
  Color fg([int alpha = 255]) => isLight
      ? Color.fromARGB(alpha, 18, 18, 18)
      : Color.fromARGB(alpha, 255, 255, 255);

  /// Seçimi tətbiq edir, bütün ekranları yenidən qurur və bazaya yazır.
  void set({AppThemeMode? mode, int? accentIndex, bool save = true}) {
    if (mode != null) this.mode = mode;
    if (accentIndex != null) this.accentIndex = accentIndex;
    notifyListeners(); // MaterialApp teması yenilənir
    _rebuildAll(); // const widget-lər də rəngi yenidən oxusun
    if (save) {
      CloudioStore.instance.saveTheme(this.mode.index, this.accentIndex);
    }
  }

  /// Bazadan oxunmuş seçimi bərpa edir.
  void restore(int modeIndex, int accent) {
    set(
      mode: AppThemeMode.values[modeIndex.clamp(0, AppThemeMode.values.length - 1)],
      accentIndex: accent.clamp(0, kAccentColors.length - 1),
      save: false,
    );
  }

  /// Bütün element ağacını "dirty" edir (Flutter-in lokalizasiya üçün tövsiyə etdiyi üsul).
  /// Rənglər qlobal oxunduğu üçün `const` widget-lər də yenidən qurulmalıdır.
  static void _rebuildAll() {
    void rebuild(Element el) {
      el.markNeedsBuild();
      el.visitChildren(rebuild);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) rebuild(root);
  }

  ThemeData get themeData => _build(brightness, fixedDark: false);

  /// Həmişə tünd qalan ekranlar (Now Playing, sözlər, profil kartı) üçün.
  ThemeData get darkData => _build(Brightness.dark, fixedDark: true);

  ThemeData _build(Brightness b, {required bool fixedDark}) {
    final dark = b == Brightness.dark;
    final background = fixedDark ? const Color(0xFF121212) : bg;
    final onBg = dark ? Colors.white : const Color(0xFF121212);
    return ThemeData(
      brightness: b,
      scaffoldBackgroundColor: background,
      colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(primary: accent, surface: background, onSurface: onBg),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onBg,
        surfaceTintColor: Colors.transparent,
      ),
      useMaterial3: true,
    );
  }
}

/// Seçilmiş temadan asılı olmayaraq həmişə tünd görünən sahə (kapaqdan rənglənən
/// ekranlar). Material mətnin default rəngini də tünd temaya görə qurur.
class DarkZone extends StatelessWidget {
  final Widget child;
  const DarkZone({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.instance.darkData,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
