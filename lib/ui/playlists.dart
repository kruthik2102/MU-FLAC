import 'package:material_ui/material_ui.dart';

import '../core/core.dart';
import 'shell.dart';
import 'theme.dart';
import 'widgets.dart';

final Listenable _libAndLists = Listenable.merge([libraryStore, playlistStore]);

Future<Playlist?> createPlaylistFlow(BuildContext context, {List<String> keys = const []}) async {
  final name = await showTextDialog(context, title: 'New playlist', hint: 'Playlist name');
  if (name == null) return null;
  final p = await playlistStore.create(name, trackKeys: keys);
  toast(keys.isEmpty ? 'Created "$name"' : 'Added to "$name"');
  return p;
}

/// Playlists list (screen 09).
class PlaylistsTab extends StatelessWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: _libAndLists,
        builder: (context, _) {
          final lists = playlistStore.playlists;
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(children: [
                const Expanded(child: Text('Playlists', style: MF.h1)),
                SquareButton(icon: Icons.add_rounded, label: 'New playlist', onTap: () => createPlaylistFlow(context)),
              ]),
            ),
            const SizedBox(height: 8),
            for (final p in lists)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ListItem(
                  leading: Collage(
                      tracks: playlistStore.tracksOf(p.id), size: 60, seed: p.name, favorites: p.isFavorites),
                  title: p.name,
                  subtitle: plural(playlistStore.playableCount(p.id), 'song'),
                  chevron: true,
                  onTap: () => Navigator.of(context).push(mfRoute(PlaylistPage(id: p.id))),
                ),
              ),
            const SizedBox(height: 12),
            Center(
              child: PillButton(
                  label: 'New playlist', icon: Icons.add_rounded, onTap: () => createPlaylistFlow(context)),
            ),
          ]);
        },
      ),
    );
  }
}

/// Playlist detail (screen 10): reorder with handles, swipe to remove.
class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MF.bg,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: _libAndLists,
          builder: (context, _) {
            final p = playlistStore.byId(id);
            if (p == null) {
              return const Column(children: [
                PageTop(),
                Expanded(child: EmptyHint(icon: Icons.queue_music_rounded, title: 'Playlist not found')),
              ]);
            }
            final entries = playlistStore.entriesOf(id);
            final tracks = [for (final e in entries) e.track];
            final total = tracks.fold<int>(0, (a, t) => a + t.durationMs);
            return CustomScrollView(slivers: [
              SliverToBoxAdapter(
                child: Column(children: [
                  PageTop(
                    trailing: p.isFavorites
                        ? null
                        : PopupMenuButton<String>(
                            tooltip: 'Playlist actions',
                            offset: const Offset(0, 50),
                            onSelected: (v) => _menu(context, p, v),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'rename', child: Text('Rename')),
                              PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
                            ],
                            child: const IgnorePointer(
                              child: SquareButton(icon: Icons.more_horiz_rounded, label: 'Playlist actions'),
                            ),
                          ),
                  ),
                  const SizedBox(height: 4),
                  Collage(tracks: tracks, size: 180, seed: p.name, favorites: p.isFavorites),
                  const SizedBox(height: 18),
                  Text(p.name, style: MF.h2, textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text('${plural(tracks.length, 'song')} · ${fmtTotal(total)}', style: MF.t3),
                  const SizedBox(height: 18),
                  PlayShuffleRow(tracks: tracks),
                  const SizedBox(height: 14),
                  if (tracks.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text('Drag ≡ to reorder · swipe left to remove', style: MF.meta),
                    ),
                ]),
              ),
              if (tracks.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 30, 32, 0),
                    child: Text(
                      p.isFavorites
                          ? 'Tap the heart on Now Playing to add songs here.'
                          : 'Add songs with ••• → Add to playlist.',
                      style: MF.t3,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                SliverReorderableList(
                  itemCount: entries.length,
                  onReorderItem: (from, to) {
                    if (from == to) return;
                    playlistStore.move(id, entries[from].index, entries[to].index);
                  },
                  proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return Dismissible(
                      key: ValueKey('${e.index}:${e.track.key}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        padding: const EdgeInsets.only(right: 24),
                        alignment: Alignment.centerRight,
                        decoration: BoxDecoration(color: MF.light, borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.delete_outline_rounded, color: MF.bg),
                      ),
                      onDismissed: (_) {
                        playlistStore.removeAt(id, e.index);
                        toast('Removed "${e.track.title}"');
                      },
                      child: TrackRow(
                        track: e.track,
                        onTap: () => playerController.playTracks(tracks, index: i),
                        onRemove: () => playlistStore.removeAt(id, e.index),
                        removeLabel: 'Remove from ${p.name}',
                        trailing: ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.fromLTRB(10, 10, 4, 10),
                            child: Icon(Icons.drag_handle_rounded, color: MF.text2, size: 22),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ]);
          },
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, Playlist p, String v) async {
    if (v == 'rename') {
      final name = await showTextDialog(context, title: 'Rename playlist', initial: p.name, action: 'Save');
      if (name != null) await playlistStore.rename(p.id, name);
    } else if (v == 'delete') {
      final nav = Navigator.of(context);
      final ok = await confirmDialog(context,
          title: 'Delete "${p.name}"?', body: 'The songs stay in your library. This can\'t be undone.');
      if (ok) {
        nav.maybePop();
        await playlistStore.delete(p.id);
      }
    }
  }
}
