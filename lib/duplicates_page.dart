import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import 'backup_types.dart' show formatBytes;
import 'main.dart' show Cover, formatDuration, kBg, kCard, kGreen, kText38, kText54, kText60;
import 'player_controller.dart';

/// Tekrar eden şarkılar səhifəsini açır (Ayarlar → Kitaplık).
void openDuplicates(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DuplicatesPage()));
}

// ---------------------------------------------------------------- aşkarlama

/// Müqayisə üçün adı sadələşdirir: kiçik hərf, ə/ç/ğ/ı/ö/ş/ü -> latın, durğu atılır,
/// sondakı " (1)" və "copy/kopya" atılır. "(remix)", "(live)" kimi sözlərə toxunmur.
String _normText(String input) {
  var t = input.toLowerCase();
  t = t.replaceAll(RegExp(r'\p{M}', unicode: true), ''); // birləşən işarələr (İ -> i̇)
  const fold = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'ə': 'e'};
  fold.forEach((k, v) => t = t.replaceAll(k, v));
  t = t.replaceAll(RegExp(r'\s*[\(\[]\s*\d+\s*[\)\]]\s*$'), ''); // "... (1)"
  t = t.replaceAll(RegExp(r'[\s\-_]*(copy|kopya|kopyasi)\s*\d*\s*$'), '');
  t = t.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
  return t;
}

String _normArtist(String a) {
  if (a.trim().isEmpty || a == kUnknownArtist) return '';
  return _normText(a);
}

/// İki mahnı eyni mahnıdırmı (adları artıq eyni normallaşdırılıb).
bool _same(Song a, Song b) {
  final aa = _normArtist(a.artist);
  final ba = _normArtist(b.artist);
  final da = a.duration;
  final db = b.duration;
  int? diff; // millisaniyə fərqi, bilinmirsə null
  if (da != null && db != null && da > Duration.zero && db > Duration.zero) {
    diff = (da.inMilliseconds - db.inMilliseconds).abs();
  }
  if (aa.isNotEmpty && ba.isNotEmpty) {
    // "Sənətçi" ilə "Sənətçi feat. X" eyni sayılır
    final artistOk = aa == ba || aa.startsWith('$ba ') || ba.startsWith('$aa ');
    if (!artistOk) return false;
    return diff == null || diff <= 5000; // müddət fərqi 5 san-dən çoxdursa başqa mahnıdır
  }
  // sənətçilərdən biri bilinmir: yalnız müddət də 2 san-dən az fərqlənirsə
  return diff != null && diff <= 2000;
}

int _sizeOf(Song s) {
  final i = s.id.lastIndexOf('|');
  return i < 0 ? 0 : (int.tryParse(s.id.substring(i + 1)) ?? 0);
}

bool _lossless(Song s) => s.ext == 'flac' || s.ext == 'wav';

/// Saxlanması təklif olunan mahnının balı.
int _score(Song s) {
  var v = 0;
  if (s.liked) v += 1000;
  v += (s.playCount > 100 ? 100 : s.playCount) * 5;
  if (_lossless(s)) v += 50;
  if (s.cover != null) v += 20;
  if (s.lyrics != null) v += 20;
  v += _sizeOf(s) ~/ (1024 * 1024); // hər MB 1 bal
  if (!kIsWeb && s.path == null) v -= 500; // səs faylı telefonda yoxdur
  return v;
}

class DupGroup {
  final List<Song> songs;
  late final Song best;
  DupGroup(this.songs) {
    best = songs.reduce((a, b) => _score(b) > _score(a) ? b : a);
  }
}

/// Kitabxanadakı təkrar mahnı qruplarını tapır.
List<DupGroup> findDuplicateGroups(List<Song> all) {
  final byTitle = <String, List<Song>>{};
  for (final s in all) {
    final t = _normText(s.title);
    if (t.length < 2) continue;
    byTitle.putIfAbsent(t, () => <Song>[]).add(s);
  }
  final groups = <DupGroup>[];
  for (final list in byTitle.values) {
    if (list.length < 2) continue;
    final parent = List<int>.generate(list.length, (i) => i);
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        if (_same(list[i], list[j])) parent[find(i)] = find(j);
      }
    }
    final clusters = <int, List<Song>>{};
    for (var i = 0; i < list.length; i++) {
      clusters.putIfAbsent(find(i), () => <Song>[]).add(list[i]);
    }
    for (final c in clusters.values) {
      if (c.length >= 2) groups.add(DupGroup(c));
    }
  }
  groups.sort((a, b) => a.best.title.toLowerCase().compareTo(b.best.title.toLowerCase()));
  return groups;
}

// ---------------------------------------------------------------- səhifə

class DuplicatesPage extends StatefulWidget {
  const DuplicatesPage({super.key});

  @override
  State<DuplicatesPage> createState() => _DuplicatesPageState();
}

class _DuplicatesPageState extends State<DuplicatesPage> {
  final PlayerController _c = PlayerController.instance;
  List<DupGroup> _groups = const [];
  final Map<int, Song> _keep = {}; // qrup indeksi -> istifadəçinin seçdiyi
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  void _recompute() {
    _groups = findDuplicateGroups(_c.songs);
    _keep.clear();
  }

  Song _keepOf(int gi) => _keep[gi] ?? _groups[gi].best;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 36),
        title: Text(title),
        content: Text(body, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç', style: TextStyle(color: kText54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _mergeGroup(int gi) async {
    final keep = _keepOf(gi);
    final removes = [
      for (final s in _groups[gi].songs)
        if (!identical(s, keep)) s,
    ];
    final ok = await _confirm(
      'Kopyalar silinsin mi?',
      '"${keep.title}" kalacak (${keep.ext.toUpperCase()}).\n'
          '${removes.length} kopya silinecek: '
          '${removes.map((s) => s.ext.toUpperCase()).join(', ')}.\n\n'
          'Çalma listeleri, beğeni ve dinleme sayısı kalan şarkıya aktarılır. '
          'Silinen kopyanın ses dosyası da silinir. Bu geri alınamaz.',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      for (final r in removes) {
        await _c.mergeDuplicate(keep, r);
      }
      _snack('${removes.length} kopya silindi');
    } catch (e) {
      _snack('Silinemedi: $e');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _recompute();
    });
  }

  Future<void> _mergeAll() async {
    final plan = <Song, List<Song>>{};
    var total = 0;
    for (var gi = 0; gi < _groups.length; gi++) {
      final keep = _keepOf(gi);
      final removes = [
        for (final s in _groups[gi].songs)
          if (!identical(s, keep)) s,
      ];
      plan[keep] = removes;
      total += removes.length;
    }
    final ok = await _confirm(
      'Hepsi temizlensin mi?',
      '${_groups.length} grupta toplam $total kopya silinecek. Her grupta '
          'seçili olan şarkı kalır (önerilen ya da senin seçtiğin).\n\n'
          'Çalma listeleri, beğeni ve dinleme sayısı kalan şarkıya aktarılır. '
          'Ses dosyaları da silinir. Bu geri alınamaz.',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      for (final e in plan.entries) {
        for (final r in e.value) {
          await _c.mergeDuplicate(e.key, r);
        }
      }
      _snack('$total kopya silindi');
    } catch (e) {
      _snack('Silinemedi: $e');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _recompute();
    });
  }

  String _details(Song s) {
    final parts = <String>[s.ext.toUpperCase()];
    final size = _sizeOf(s);
    if (size > 0) parts.add(formatBytes(size));
    if (s.duration != null) parts.add(formatDuration(s.duration!));
    parts.add('${s.playCount} dinleme');
    if (s.liked) parts.add('♥');
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Tekrar eden şarkılar', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_groups.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : _mergeAll,
              child: const Text('Hepsini temizle', style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
      body: _groups.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Tekrar eden şarkı bulunamadı.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kText60),
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.of(context).padding.bottom),
              children: [
                Text(
                  '${_groups.length} grup bulundu. Eşleşme şarkı adı, sanatçı ve süreye '
                  'göre yapılır; yanlış eşleşme olabilir, silmeden önce kontrol et. '
                  'Kalmasını istediğin kopyaya dokun.',
                  style: TextStyle(color: kText60, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                if (_busy) const LinearProgressIndicator(minHeight: 2),
                for (var gi = 0; gi < _groups.length; gi++) _groupCard(gi),
              ],
            ),
    );
  }

  Widget _groupCard(int gi) {
    final g = _groups[gi];
    final keep = _keepOf(gi);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          for (final s in g.songs)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _busy ? null : () => setState(() => _keep[gi] = s),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      identical(s, keep)
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: identical(s, keep) ? kGreen : kText38,
                    ),
                    const SizedBox(width: 10),
                    Cover(size: 44, bytes: s.cover),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            s.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: kText60, fontSize: 12),
                          ),
                          Text(_details(s), style: TextStyle(color: kText54, fontSize: 11)),
                          if (identical(s, g.best))
                            Text(
                              'Önerilen',
                              style: TextStyle(
                                color: kGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _mergeGroup(gi),
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
              label: const Text(
                'Seçilen dışındakileri sil',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
