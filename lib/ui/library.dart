import 'package:material_ui/material_ui.dart';

import '../core/core.dart';
import 'sheets.dart';
import 'shell.dart';
import 'theme.dart';
import 'widgets.dart';

class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key});
  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  int _seg = settingsStore.getOr<int>('librarySeg', 0);
  List<Track>? _songsCache;
  List<Track>? _songsSource;

  List<Track> _songs() {
    final src = libraryStore.tracks;
    if (!identical(src, _songsSource)) {
      _songsSource = src;
      _songsCache = [...src]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return _songsCache!;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: libraryStore,
        builder: (context, _) {
          final empty = libraryStore.isEmpty;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(children: [
                const Expanded(child: Text('Library', style: MF.h1)),
                if (libraryStore.scanning && !empty)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: MF.text2)),
                  ),
                SquareButton(
                  icon: Icons.search_rounded,
                  label: 'Search',
                  onTap: empty ? null : () => Navigator.of(context).push(mfRoute(const SearchPage())),
                ),
              ]),
            ),
            if (empty)
              const Expanded(child: EmptyLibrary())
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Segmented(
                  labels: const ['Albums', 'Artists', 'Songs'],
                  index: _seg,
                  onChanged: (i) {
                    setState(() => _seg = i);
                    settingsStore.set('librarySeg', i);
                  },
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: MF.text,
                  backgroundColor: MF.mini,
                  onRefresh: () => libraryStore.rescan(),
                  child: switch (_seg) {
                    0 => _AlbumsGrid(albums: libraryStore.albums),
                    1 => _ArtistsList(artists: libraryStore.artists),
                    _ => _SongsList(tracks: _songs()),
                  },
                ),
              ),
            ],
          ]);
        },
      ),
    );
  }
}

class _AlbumsGrid extends StatelessWidget {
  const _AlbumsGrid({required this.albums});
  final List<Album> albums;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 18,
        crossAxisSpacing: 16,
        childAspectRatio: .74,
      ),
      itemCount: albums.length,
      itemBuilder: (context, i) {
        final a = albums[i];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(mfRoute(AlbumPage(albumId: a.id))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 1,
              child: CoverArt(path: a.artPath, seed: a.title, radius: 16, shadow: MF.cardShadow),
            ),
            const SizedBox(height: 10),
            Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: MF.t2.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(a.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: MF.t3),
          ]),
        );
      },
    );
  }
}

class _ArtistsList extends StatelessWidget {
  const _ArtistsList({required this.artists});
  final List<Artist> artists;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      itemCount: artists.length,
      itemBuilder: (context, i) {
        final a = artists[i];
        return ListItem(
          leading: CoverArt(path: a.artPath, seed: a.name, size: 52, circle: true),
          title: a.name,
          subtitle: '${plural(a.albums.length, 'album')} · ${plural(a.tracks.length, 'song')}',
          chevron: true,
          onTap: () => Navigator.of(context).push(mfRoute(ArtistPage(name: a.name))),
        );
      },
    );
  }
}

class _SongsList extends StatelessWidget {
  const _SongsList({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: tracks.length,
      itemBuilder: (context, i) =>
          TrackRow(track: tracks[i], onTap: () => playerController.playTracks(tracks, index: i)),
    );
  }
}

class AlbumPage extends StatelessWidget {
  const AlbumPage({super.key, required this.albumId});
  final String albumId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MF.bg,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: libraryStore,
          builder: (context, _) {
            final a = libraryStore.album(albumId);
            if (a == null) {
              return const Column(children: [
                PageTop(),
                Expanded(child: EmptyHint(icon: Icons.album_rounded, title: 'Album not found')),
              ]);
            }
            final multiDisc = a.discCount > 1;
            final rows = <Widget>[];
            int? disc;
            for (var i = 0; i < a.tracks.length; i++) {
              final t = a.tracks[i];
              if (multiDisc && t.discNo != disc) {
                disc = t.discNo;
                rows.add(SectionLabel('Disc ${disc ?? 1}', padding: const EdgeInsets.fromLTRB(24, 16, 20, 6)));
              }
              rows.add(TrackRow(
                track: t,
                number: t.trackNo ?? (i + 1),
                onTap: () => playerController.playTracks(a.tracks, index: i),
              ));
            }
            final meta = [
              if (a.year != null) '${a.year}',
              plural(a.tracks.length, 'track'),
              fmtTotal(a.durationMs),
            ].join(' · ');
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              PageTop(
                trailing: SquareButton(
                  icon: Icons.more_horiz_rounded,
                  label: 'Album actions',
                  onTap: () => _albumActions(context, a),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: CoverArt(path: a.artPath, seed: a.title, size: 220, radius: 16, shadow: MF.heroShadow),
              ),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(children: [
                  Text(a.title, style: MF.h2, textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(mfRoute(ArtistPage(name: a.artist))),
                    child: Text(a.artist, style: MF.t2.copyWith(color: MF.text3), textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Flexible(child: Text(meta, style: MF.t3, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    FormatPill(a.formatLabel, grey: true),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),
              PlayShuffleRow(tracks: a.tracks),
              const SizedBox(height: 18),
              ...rows,
            ]);
          },
        ),
      ),
    );
  }

  void _albumActions(BuildContext context, Album a) {
    showMfSheet(context, (ctx) {
      void act(VoidCallback f) {
        Navigator.of(ctx).pop();
        f();
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
        child: Group(children: [
          ListItem(icon: Icons.playlist_play_rounded, title: 'Play next', onTap: () => act(() {
                playerController.playNext(a.tracks);
                toast('Playing next');
              })),
          ListItem(icon: Icons.queue_rounded, title: 'Add to queue', onTap: () => act(() {
                playerController.addToQueue(a.tracks);
                toast('Added to queue');
              })),
          ListItem(
              icon: Icons.playlist_add_rounded,
              title: 'Add to playlist…',
              onTap: () => act(() => showAddToPlaylist(context, a.tracks))),
          ListItem(
              icon: Icons.person_rounded,
              title: 'Go to artist',
              onTap: () => act(() => Navigator.of(context).push(mfRoute(ArtistPage(name: a.artist))))),
        ]),
      );
    });
  }
}

class ArtistPage extends StatelessWidget {
  const ArtistPage({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MF.bg,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: libraryStore,
          builder: (context, _) {
            final a = libraryStore.artist(name);
            if (a == null) {
              return const Column(children: [
                PageTop(),
                Expanded(child: EmptyHint(icon: Icons.person_rounded, title: 'Artist not found')),
              ]);
            }
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              const PageTop(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(children: [
                  CoverArt(path: a.artPath, seed: a.name, size: 72, circle: true, shadow: MF.cardShadow),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.name, style: MF.h1, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text('${plural(a.albums.length, 'album')} · ${plural(a.tracks.length, 'song')}', style: MF.t3),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              PlayShuffleRow(tracks: a.tracks),
              const SectionLabel('Albums'),
              SizedBox(
                height: 196,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: a.albums.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) {
                    final al = a.albums[i];
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(mfRoute(AlbumPage(albumId: al.id))),
                      child: SizedBox(
                        width: 140,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          CoverArt(path: al.artPath, seed: al.title, size: 140, radius: 16, shadow: MF.cardShadow),
                          const SizedBox(height: 8),
                          Text(al.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: MF.t2),
                          Text(al.year?.toString() ?? '', style: MF.t3),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              const SectionLabel('Songs', padding: EdgeInsets.fromLTRB(20, 12, 20, 8)),
              for (var i = 0; i < a.tracks.length; i++)
                TrackRow(track: a.tracks[i], onTap: () => playerController.playTracks(a.tracks, index: i)),
            ]);
          },
        ),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctl = TextEditingController();
  List<Track> _results = const [];

  void _run(String q) => setState(() => _results = q.trim().isEmpty ? const [] : libraryStore.searchTracks(q));

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MF.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                SquareButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    label: 'Back',
                    onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: MF.wellDecoration.copyWith(borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.search_rounded, color: MF.text2, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _ctl,
                          autofocus: true,
                          style: MF.t2,
                          onChanged: _run,
                          decoration: InputDecoration(
                            hintText: 'Songs, artists, albums',
                            hintStyle: MF.t2.copyWith(color: MF.text2),
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(_ctl.text.isEmpty ? 'Type to search your library' : 'No matches', style: MF.t3))
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 6, bottom: 24),
                    itemCount: _results.length,
                    itemBuilder: (context, i) => TrackRow(
                      track: _results[i],
                      onTap: () => playerController.playTracks(_results, index: i),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}
