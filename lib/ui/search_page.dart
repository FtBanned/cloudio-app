part of '../main.dart';

// ================= Arama =================
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final q = _query.trim().toLowerCase();
        final matches = <int>[
          for (var i = 0; i < c.songs.length; i++)
            if (q.isNotEmpty &&
                (c.songs[i].title.toLowerCase().contains(q) ||
                    c.songs[i].artist.toLowerCase().contains(q) ||
                    c.songs[i].album.toLowerCase().contains(q) ||
                    c.songs[i].genre.toLowerCase().contains(q)))
              i,
        ];

        final matchSongs = [for (final i in matches) c.songs[i]];

        // Başlıq və axtarış xanası sabit qalır, nəticələr aşağıda sürüşür
        // (xana siyahının içində olsaydı, aşağı sürüşəndə yazılan mətn itərdi).
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              const Row(
                children: [
                  ProfileAvatar(),
                  SizedBox(width: 12),
                  Text('Ara',
                      style:
                          TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: Colors.black),
                cursorColor: Colors.black,
                decoration: InputDecoration(
                  hintText: 'Ne dinlemek istiyorsun?',
                  hintStyle: const TextStyle(color: Colors.black54),
                  prefixIcon: const Icon(Icons.search, color: Colors.black),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: q.isEmpty
                    ? _GenreBrowser(genres: groupGenres(c.songs))
                    : matchSongs.isEmpty
                        ? Center(
                            child: Text('Sonuç bulunamadı',
                                style: TextStyle(color: kText60)),
                          )
                        : ListView.builder(
                            itemCount: matchSongs.length,
                            itemBuilder: (context, i) => SongTile(
                              key: ValueKey(matchSongs[i].id),
                              song: matchSongs[i],
                              queue: matchSongs,
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Axtarışda boş sorğuda göstərilən "Janrlara göz at" bölməsi.
class _GenreBrowser extends StatelessWidget {
  final List<SongGroup> genres;
  const _GenreBrowser({required this.genres});

  static const _colors = [
    Color(0xFFE91E8C),
    Color(0xFF00695C),
    Color(0xFF283593),
    Color(0xFF8E24AA),
    Color(0xFFD84315),
    Color(0xFF1565C0),
    Color(0xFF558B2F),
    Color(0xFFAD1457),
  ];

  Color _colorFor(String name) {
    var h = 0;
    for (final u in name.toLowerCase().codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return _colors[h % _colors.length];
  }

  @override
  Widget build(BuildContext context) {
    if (genres.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Henüz janr bilgisi yok.\nŞarkıların etiketinde janr varsa burada görünür; '
            'şarkı menüsünden de elle ekleyebilirsin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kText60),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Janrlara göz at',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.0,
            children: [
              for (final g in genres)
                CategoryTile(
                  g.name,
                  _colorFor(g.name),
                  subtitle: '${g.songs.length} şarkı',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CollectionPage.genre(g.name),
                  )),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class CategoryTile extends StatelessWidget {
  final String label;
  final Color color;
  final String? subtitle;
  final VoidCallback? onTap;
  const CategoryTile(this.label, this.color,
      {super.key, this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (subtitle != null)
              Text(subtitle!,
                  style: TextStyle(fontSize: 12, color: kText70)),
          ],
        ),
      ),
    );
  }
}
