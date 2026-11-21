part of '../main.dart';

// ================= Sıralama =================
enum SongSort { standard, newest, title, artist }

String songSortLabel(SongSort s) => switch (s) {
  SongSort.standard => 'Varsayılan',
  SongSort.newest => 'Son eklenen',
  SongSort.title => 'Ada göre',
  SongSort.artist => 'Sanatçıya göre',
};

int _cmpText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// Albom sırası: disk -> trek nömrəsi. Nömrəsi olmayanlar sonda, öz əvvəlki sırasında qalır.
/// Heç bir mahnıda nömrə yoxdursa siyahı dəyişmir.
List<Song> albumOrder(List<Song> src) {
  if (src.every((s) => s.trackNo == 0)) return List<Song>.of(src);
  final idx = <Song, int>{for (var i = 0; i < src.length; i++) src[i]: i};
  final l = List<Song>.of(src);
  int big(int v) => v == 0 ? 1 << 30 : v; // 0 = bilinmir, sona
  l.sort((a, b) {
    var r = big(a.discNo == 0 ? 1 : a.discNo).compareTo(big(b.discNo == 0 ? 1 : b.discNo));
    if (r != 0) return r;
    r = big(a.trackNo).compareTo(big(b.trackNo));
    return r != 0 ? r : idx[a]!.compareTo(idx[b]!);
  });
  return l;
}

/// "2019 • Pop • 12 şarkı • 47 dk" (il və janr yalnız varsa).
String albumInfo(List<Song> list) {
  final years = [
    for (final s in list)
      if (s.year > 0) s.year,
  ];
  final genre = list
      .firstWhere((s) => s.genre.trim().isNotEmpty, orElse: () => list.first)
      .genre
      .trim();
  final parts = <String>[
    if (years.isNotEmpty) '${years.reduce((a, b) => a < b ? a : b)}',
    if (genre.isNotEmpty) genre,
    countAndTotal(list),
  ];
  return parts.join(' • ');
}

/// Janra görə qruplar (böyükdən kiçiyə). Janrı olmayanlar daxil edilmir.
List<SongGroup> groupGenres(List<Song> src) {
  final map = <String, SongGroup>{};
  for (final s in src) {
    final g = s.genre.trim();
    if (g.isEmpty) continue;
    map.putIfAbsent(g.toLowerCase(), () => SongGroup(g)).songs.add(s);
  }
  final l = map.values.toList()
    ..sort((a, b) {
      final r = b.songs.length.compareTo(a.songs.length);
      return r != 0 ? r : _cmpText(a.name, b.name);
    });
  return l;
}

/// [src] siyahısının sıralanmış KOPYASINI qaytarır (orijinal dəyişmir).
List<Song> sortedSongs(List<Song> src, SongSort sort) {
  final l = List<Song>.of(src);
  switch (sort) {
    case SongSort.standard:
      break; // olduğu kimi
    case SongSort.newest:
      l.sort((a, b) => b.seq.compareTo(a.seq));
    case SongSort.title:
      l.sort((a, b) => _cmpText(a.title, b.title));
    case SongSort.artist:
      l.sort((a, b) {
        final r = _cmpText(a.artist, b.artist);
        return r != 0 ? r : _cmpText(a.title, b.title);
      });
  }
  return l;
}

/// Aşağıdan açılan "Sırala" menyusu. Seçilən variantın indeksini qaytarır (ləğv: null).
Future<int?> showSortSheet(
  BuildContext context, {
  required List<String> options,
  required int selected,
}) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: kCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Sırala', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          for (var i = 0; i < options.length; i++)
            ListTile(
              title: Text(
                options[i],
                style: TextStyle(
                  color: i == selected ? kGreen : null,
                  fontWeight: i == selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: i == selected ? Icon(Icons.check, color: kGreen) : null,
              onTap: () => Navigator.pop(ctx, i),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// "⇅ Varsayılan" şəklində kiçik sıralama çubuğu.
class SortBar extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const SortBar({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swap_vert, size: 20),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
