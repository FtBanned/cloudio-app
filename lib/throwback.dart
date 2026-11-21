import 'package:flutter/material.dart';

import 'main.dart' show Cover, kCard, kGreen, kText, kText38, kText54, kText60;
import 'persistence.dart' show PlayEvent;
import 'player_controller.dart';

/// TEST DÜYMƏSİ:
///  -1  = normal rejim (həqiqətən bir il əvvəlki bu gün)
///   0  = bu gün (indi dinlədiklərini görmək üçün test)
///   1  = dünən, 2 = srağagün və s.
/// Test bitəndə mütləq -1 yaz.
const int kThrowbackTestDays = -1;

const _months = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
];

class _Item {
  final String songId;
  final String title;
  final String artist;
  int count = 0;
  _Item(this.songId, this.title, this.artist);
}

class _Result {
  final DateTime day;
  final bool exact; // true: tam həmin gün, false: ±3 gün
  final int plays;
  final int uniqueSongs;
  final List<_Item> top;
  const _Result({
    required this.day,
    required this.exact,
    required this.plays,
    required this.uniqueSongs,
    required this.top,
  });
}

/// Dinləmə tarixçəsindən "bir il əvvəlki bu gün"ü hesablayır. Heç nə yoxdursa null.
_Result? _compute(PlayerController c) {
  final now = DateTime.now();
  final day = kThrowbackTestDays >= 0
      ? DateTime(now.year, now.month, now.day - kThrowbackTestDays)
      : DateTime(now.year - 1, now.month, now.day);

  var exact = true;
  List<PlayEvent> events =
      c.playsBetween(day, DateTime(day.year, day.month, day.day + 1));
  if (events.isEmpty) {
    exact = false;
    events = c.playsBetween(DateTime(day.year, day.month, day.day - 3),
        DateTime(day.year, day.month, day.day + 4));
  }
  if (events.isEmpty) return null;

  final map = <String, _Item>{};
  for (final e in events) {
    final it = map.putIfAbsent(e.songId, () => _Item(e.songId, e.title, e.artist));
    it.count++;
  }
  final list = map.values.toList()
    ..sort((a, b) {
      final x = b.count.compareTo(a.count);
      return x != 0 ? x : a.title.compareTo(b.title);
    });
  return _Result(
    day: day,
    exact: exact,
    plays: events.length,
    uniqueSongs: list.length,
    top: list.length > 3 ? list.sublist(0, 3) : list,
  );
}

/// Ana sayfa kartı: "Geçen yıl bu gün şunu dinliyordun". Veri yoksa görünmez.
class ThrowbackCard extends StatefulWidget {
  const ThrowbackCard({super.key});

  @override
  State<ThrowbackCard> createState() => _ThrowbackCardState();
}

class _ThrowbackCardState extends State<ThrowbackCard> {
  String _key = '';
  _Result? _cache;

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final today = DateTime.now();
        final key = '${c.playLog.length}|${today.year}-${today.month}-${today.day}';
        if (key != _key) {
          _key = key;
          _cache = _compute(c);
        }
        final r = _cache;
        if (r == null) return const SizedBox.shrink();

        final title = kThrowbackTestDays >= 0
            ? 'Test: $kThrowbackTestDays gün önce'
            : (r.exact ? 'Geçen yıl bu gün' : 'Geçen yıl bu günlerde');
        final dateTxt = '${r.day.day} ${_months[r.day.month - 1]} ${r.day.year}';

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kGreen.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.history, color: kGreen, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    Text(dateTxt,
                        style: TextStyle(color: kText54, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                for (final it in r.top) _row(c, it),
                const SizedBox(height: 6),
                Text(
                    '${r.exact ? 'O gün' : 'O günlerde'} ${r.plays} dinleme • '
                    '${r.uniqueSongs} farklı şarkı',
                    style: TextStyle(color: kText38, fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(PlayerController c, _Item it) {
    Song? found;
    for (final s in c.songs) {
      if (s.id == it.songId) {
        found = s;
        break;
      }
    }
    final song = found; // kitaplıqda yoxdursa null (silinib)
    return InkWell(
      onTap: song == null ? null : () => c.playSong(song),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Cover(size: 48, bytes: song?.cover),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: song == null ? kText38 : kText)),
                  Text(it.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: kText60, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('${it.count} kez',
                style: TextStyle(color: kText60, fontSize: 12)),
            if (song != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.play_arrow, color: kGreen),
            ],
          ],
        ),
      ),
    );
  }
}
