part of '../main.dart';

// ================= Şarkı bilgisini düzenleme =================
void openEditSong(BuildContext context, Song song) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => EditSongPage(song: song),
  ));
}

class EditSongPage extends StatefulWidget {
  final Song song;
  const EditSongPage({super.key, required this.song});

  @override
  State<EditSongPage> createState() => _EditSongPageState();
}

class _EditSongPageState extends State<EditSongPage> {
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _album;
  late final TextEditingController _genre;
  late final TextEditingController _year;
  late final TextEditingController _track;
  Uint8List? _cover;
  bool _coverChanged = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = widget.song;
    _title = TextEditingController(text: s.title);
    _artist = TextEditingController(
        text: s.artist == kUnknownArtist ? '' : s.artist);
    _album = TextEditingController(text: s.album);
    _genre = TextEditingController(text: s.genre);
    _year = TextEditingController(text: s.year > 0 ? '${s.year}' : '');
    _track = TextEditingController(text: s.trackNo > 0 ? '${s.trackNo}' : '');
    _cover = s.cover;
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _genre.dispose();
    _year.dispose();
    _track.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickCover() async {
    try {
      final b = await PlayerController.instance.pickCoverImage();
      if (b == null || !mounted) return;
      setState(() {
        _cover = b;
        _coverChanged = true;
      });
    } catch (_) {
      _toast('Resim okunamadı');
    }
  }

  /// İnternette serbest aramayla sonuç listesi açar; seçilen sonucun adı, sanatçısı,
  /// albümü ve kapağı alanlara doldurulur (Kaydet'e basana kadar değişmez).
  Future<void> _openSearch() async {
    final q = '${_artist.text} ${_title.text}'.trim();
    final picked = await showModalBottomSheet<CoverCandidate>(
      context: context,
      backgroundColor: kCard,
      shape: _sheetShape,
      isScrollControlled: true,
      builder: (_) => _CandidateSheet(initial: q),
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    final img = await fetchCoverImage(picked.artUrl);
    if (!mounted) return;
    setState(() {
      _title.text = picked.title;
      _artist.text = picked.artist;
      _album.text = picked.album;
      if (img != null) {
        _cover = img;
        _coverChanged = true;
      }
      _busy = false;
    });
    if (img == null) _toast('Kapak indirilemedi, bilgiler dolduruldu');
  }

  Future<void> _save() async {
    await PlayerController.instance.updateSongInfo(
      widget.song,
      title: _title.text,
      artist: _artist.text,
      album: _album.text,
      genre: _genre.text,
      year: int.tryParse(_year.text.trim()) ?? 0,
      trackNo: int.tryParse(_track.text.trim()) ?? 0,
      cover: _cover,
      coverChanged: _coverChanged,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        title: const Text('Şarkı bilgilerini düzenle'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text('Kaydet',
                style: TextStyle(color: kGreen, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: GestureDetector(
              onTap: _busy ? null : _pickCover,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Cover(size: 180, bytes: _cover),
                  if (_busy)
                    CircularProgressIndicator(color: kGreen),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickCover,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Resim seç'),
              ),
              if (kOnlineCovers)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openSearch,
                  icon: const Icon(Icons.search),
                  label: const Text('İnternette ara'),
                ),
              if (_cover != null)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _cover = null;
                            _coverChanged = true;
                          }),
                  icon: const Icon(Icons.hide_image_outlined),
                  label: const Text('Kapağı kaldır'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Başlık'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _artist,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Sanatçı'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _album,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Albüm'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _genre,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Janr'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration:
                      const InputDecoration(labelText: 'Yıl', counterText: ''),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _track,
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                  decoration: const InputDecoration(
                      labelText: 'Albümdeki sıra', counterText: ''),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


/// "İnternette ara" penceresi: serbest metinle arar, sonuç listesinden seçtirir.
class _CandidateSheet extends StatefulWidget {
  final String initial;
  const _CandidateSheet({required this.initial});

  @override
  State<_CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends State<_CandidateSheet> {
  late final TextEditingController _q;
  List<CoverCandidate> _results = const [];
  bool _loading = false;
  String? _error;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _q = TextEditingController(text: widget.initial);
    if (widget.initial.trim().isNotEmpty) _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await searchCandidates(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        _searched = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Arama yapılamadı, bağlantını kontrol et';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: h * 0.8,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('İnternette ara',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Bir sonuca dokun: ad, sanatçı, albüm ve kapak doldurulur.',
                    style: TextStyle(color: kText54, fontSize: 12)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'Sanatçı ve şarkı adı',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: kGreen))
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: TextStyle(color: kText60)))
                      : (_searched && _results.isEmpty)
                          ? Center(
                              child: Text('Sonuç yok, aramayı değiştir',
                                  style: TextStyle(color: kText60)))
                          : ListView.builder(
                              itemCount: _results.length,
                              itemBuilder: (_, i) {
                                final r = _results[i];
                                return ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.network(
                                      r.thumbUrl,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 48,
                                        height: 48,
                                        color: Colors.grey.shade800,
                                        child: const Icon(Icons.music_note),
                                      ),
                                    ),
                                  ),
                                  title: Text(r.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                      r.album.isEmpty
                                          ? r.artist
                                          : '${r.artist} • ${r.album}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: kText60)),
                                  onTap: () => Navigator.pop(context, r),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
