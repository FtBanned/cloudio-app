import 'package:material_ui/material_ui.dart';

import 'app_theme.dart' show DarkZone;
import 'main.dart' show kCard, kGreen, kText, kText12, kText38, kText54, kText60, kText70;
import 'persistence.dart' show PlayEvent;
import 'player_controller.dart';

/// Şəxsi statistika səhifəsini açır (Ayarlar və profil kartından çağırılır).
void openStats(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StatsPage()));
}

enum _Range { thisMonth, lastMonth, all }

const _trMonths = [
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

String _dur(Duration d) {
  final days = d.inDays;
  final h = d.inHours % 24;
  final m = d.inMinutes % 60;
  if (days > 0) return '$days gün $h sa';
  if (d.inHours > 0) return '${d.inHours} sa $m dk';
  if (d.inMinutes > 0) return '${d.inMinutes} dk';
  return '0 dk';
}

/// Bir mahnı / sənətçi / janr üzrə cəm.
class _Agg {
  final String name;
  final String sub; // mahnı üçün sənətçi
  int count = 0;
  int ms = 0;
  _Agg(this.name, [this.sub = '']);
}

class _Data {
  int plays = 0;
  int ms = 0;
  int uniqueSongs = 0;
  int uniqueArtists = 0;
  List<_Agg> artists = [];
  List<_Agg> songs = [];
  List<_Agg> genres = [];
}

bool _knownArtist(String a) => a.trim().isNotEmpty && a != kUnknownArtist;

List<_Agg> _top(Map<String, _Agg> m, [int n = 5]) {
  final l = m.values.toList()
    ..sort((a, b) {
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : b.ms.compareTo(a.ms);
    });
  return l.length > n ? l.sublist(0, n) : l;
}

_Data _build(PlayerController c, _Range r) {
  final d = _Data();
  final artists = <String, _Agg>{};
  final songs = <String, _Agg>{};
  final genres = <String, _Agg>{};

  void add(String id, String title, String artist, String genre, int count, int ms) {
    d.plays += count;
    d.ms += ms;
    final sg = songs.putIfAbsent(id, () => _Agg(title, artist));
    sg.count += count;
    sg.ms += ms;
    if (_knownArtist(artist)) {
      final a = artists.putIfAbsent(artist, () => _Agg(artist));
      a.count += count;
      a.ms += ms;
    }
    if (genre.trim().isNotEmpty) {
      final g = genres.putIfAbsent(genre, () => _Agg(genre));
      g.count += count;
      g.ms += ms;
    }
  }

  if (r == _Range.all) {
    // Bütün dinləmələr: mahnıların öz sayğacından (köhnə dinləmələr də daxil)
    for (final s in c.songs) {
      if (s.playCount <= 0) continue;
      add(
        s.id,
        s.title,
        s.artist,
        s.genre,
        s.playCount,
        (s.duration?.inMilliseconds ?? 0) * s.playCount,
      );
    }
  } else {
    final now = DateTime.now();
    final start = r == _Range.thisMonth
        ? DateTime(now.year, now.month)
        : DateTime(now.year, now.month - 1);
    final end = r == _Range.thisMonth ? null : DateTime(now.year, now.month);
    final durById = {for (final s in c.songs) s.id: s.duration?.inMilliseconds ?? 0};
    for (final e in c.playsBetween(start, end)) {
      final ms = e.durMs > 0 ? e.durMs : (durById[e.songId] ?? 0);
      add(e.songId, e.title, e.artist, e.genre, 1, ms);
    }
  }
  d.uniqueSongs = songs.length;
  d.uniqueArtists = artists.length;
  d.artists = _top(artists);
  d.songs = _top(songs);
  d.genres = _top(genres);
  return d;
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  _Range _range = _Range.thisMonth;

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kişisel istatistik', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final d = _build(c, _range);
          final now = DateTime.now();
          final prev = DateTime(now.year, now.month - 1);
          final periodName = switch (_range) {
            _Range.thisMonth => 'Bu ay',
            _Range.lastMonth => 'Geçen ay',
            _Range.all => 'Tümü',
          };
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.of(context).padding.bottom),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final r in _Range.values)
                    _RangeChip(
                      label: switch (r) {
                        _Range.thisMonth => '${_trMonths[now.month - 1]} (bu ay)',
                        _Range.lastMonth => _trMonths[prev.month - 1],
                        _Range.all => 'Tümü',
                      },
                      selected: _range == r,
                      onTap: () => setState(() => _range = r),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (d.plays == 0)
                _Empty(
                  text: _range == _Range.all
                      ? 'Henüz hiçbir şey dinlemedin.\nBir şarkıyı 30 saniye dinle, burada görünecek.'
                      : '$periodName için dinleme yok.',
                )
              else ...[
                _HeroCard(data: d, period: periodName),
                const SizedBox(height: 16),
                if (d.artists.isNotEmpty) ...[
                  _TopArtistCard(
                    artist: d.artists.first,
                    total: d.plays,
                    title: switch (_range) {
                      _Range.thisMonth => 'Bu ay en çok dinlediğin sanatçı',
                      _Range.lastMonth => 'Geçen ay en çok dinlediğin sanatçı',
                      _Range.all => 'En çok dinlediğin sanatçı',
                    },
                  ),
                  const _Gap(),
                  _RankCard(title: 'En çok dinlenen sanatçılar', items: d.artists, unit: 'kez'),
                  const _Gap(),
                ],
                _RankCard(
                  title: 'En çok dinlenen şarkılar',
                  items: d.songs,
                  unit: 'kez',
                  showSub: true,
                ),
                if (d.genres.isNotEmpty) ...[
                  const _Gap(),
                  _RankCard(title: 'Janrlar', items: d.genres, unit: 'kez'),
                ],
              ],
              if (_range != _Range.all && c.untrackedPlays > 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Not: güncellemeden önceki ${c.untrackedPlays} dinlemenin tarihi '
                  'bilinmiyor, bu yüzden yalnızca "Tümü" bölümünde sayılır.',
                  style: TextStyle(color: kText38, fontSize: 11),
                ),
              ],
              const _Gap(),
              _ActivityCard(log: c.playLog),
            ],
          );
        },
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap();
  @override
  Widget build(BuildContext context) => const SizedBox(height: 16);
}

class _RangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RangeChip({required this.label, required this.selected, required this.onTap});

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
        child: Text(
          label,
          style: TextStyle(color: selected ? Colors.black : kText, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 64),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: kText60),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20)),
    child: child,
  );
}

/// "Ümumi dinləmə vaxtı" + dinləmə / fərqli mahnı sayı.
class _HeroCard extends StatelessWidget {
  final _Data data;
  final String period;
  const _HeroCard({required this.data, required this.period});

  @override
  Widget build(BuildContext context) {
    return DarkZone(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B5D2A), Color(0xFF121212)],
          ),
          border: Border.all(color: kGreen.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Toplam dinleme süresi • $period',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              data.ms > 0 ? _dur(Duration(milliseconds: data.ms)) : '—',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: kGreen),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _MiniStat(value: '${data.plays}', label: 'Dinleme'),
                _MiniStat(value: '${data.uniqueSongs}', label: 'Farklı şarkı'),
                _MiniStat(value: '${data.uniqueArtists}', label: 'Sanatçı'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  const _MiniStat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class _TopArtistCard extends StatelessWidget {
  final _Agg artist;
  final int total;
  final String title;
  const _TopArtistCard({required this.artist, required this.total, required this.title});

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0 : (artist.count * 100 / total).round();
    return _Card(
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: kGreen,
            child: Text(
              artist.name.trim().characters.first.toUpperCase(),
              style: const TextStyle(
                color: Colors.black,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: kText60, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  artist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  '${artist.count} dinleme • toplamın %$share',
                  style: TextStyle(color: kText70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sıralı siyahı: ad, sayğac və nisbi zolaq.
class _RankCard extends StatelessWidget {
  final String title;
  final List<_Agg> items;
  final String unit;
  final bool showSub;
  const _RankCard({
    required this.title,
    required this.items,
    required this.unit,
    this.showSub = false,
  });

  @override
  Widget build(BuildContext context) {
    final maxCount = items.isEmpty ? 1 : items.first.count;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: i == 0 ? kGreen : kText54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          showSub && items[i].sub.isNotEmpty
                              ? '${items[i].name} • ${items[i].sub}'
                              : items[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${items[i].count} $unit',
                        style: TextStyle(color: kText60, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: items[i].count / maxCount,
                      minHeight: 5,
                      backgroundColor: kText12,
                      valueColor: AlwaysStoppedAnimation<Color>(i == 0 ? kGreen : kText38),
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

/// Son 14 gün çubuqları, ən aktiv vaxt və ardıcıl gün sayı (dinləmə tarixçəsindən).
class _ActivityCard extends StatelessWidget {
  final List<PlayEvent> log;
  const _ActivityCard({required this.log});

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  @override
  Widget build(BuildContext context) {
    final today = _day(DateTime.now());
    final perDay = <DateTime, int>{};
    final perHour = List<int>.filled(24, 0);
    for (final e in log) {
      final t = DateTime.fromMillisecondsSinceEpoch(e.ts);
      perDay[_day(t)] = (perDay[_day(t)] ?? 0) + 1;
      perHour[t.hour]++;
    }

    // ardıcıl günlər (bu gün dinləməyibsə dünəndən sayılır)
    var streak = 0;
    var d = perDay.containsKey(today) ? today : DateTime(today.year, today.month, today.day - 1);
    while (perDay.containsKey(d)) {
      streak++;
      d = DateTime(d.year, d.month, d.day - 1);
    }

    final days = [for (var i = 13; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
    final counts = [for (final x in days) perDay[x] ?? 0];
    final maxC = counts.fold<int>(0, (m, v) => v > m ? v : m);

    var peakHour = -1;
    var peakVal = 0;
    for (var h = 0; h < 24; h++) {
      if (perHour[h] > peakVal) {
        peakVal = perHour[h];
        peakHour = h;
      }
    }
    String part(int h) => h >= 5 && h < 12
        ? 'sabah'
        : h >= 12 && h < 17
        ? 'gündüz'
        : h >= 17 && h < 22
        ? 'akşam'
        : 'gece';

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Etkinlik • son 14 gün',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          if (maxC == 0)
            Text('Son 14 günde dinleme yok.', style: TextStyle(color: kText54, fontSize: 13))
          else
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < days.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: counts[i] == 0 ? 3 : 4 + 56 * counts[i] / maxC,
                              decoration: BoxDecoration(
                                color: counts[i] == 0
                                    ? kText12
                                    : (i == days.length - 1
                                          ? kGreen
                                          : kGreen.withValues(alpha: 0.6)),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${days[i].day}',
                              style: TextStyle(
                                fontSize: 9,
                                color: i == days.length - 1 ? kGreen : kText38,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              _MiniStat(value: streak == 0 ? '—' : '$streak gün', label: 'Üst üste dinleme'),
              _MiniStat(
                value: peakHour < 0 ? '—' : '${peakHour.toString().padLeft(2, '0')}:00',
                label: peakHour < 0 ? 'En aktif saat' : 'En aktif saat (${part(peakHour)})',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
