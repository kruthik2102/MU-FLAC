import 'package:material_ui/material_ui.dart' hide RepeatMode;

import '../core/core.dart';
import 'playlists.dart';
import 'shell.dart';
import 'theme.dart';
import 'widgets.dart';

Widget _sheetHeader(Track t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(children: [
        CoverArt(path: t.artPath, seed: t.album, size: 52, radius: 9),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: MF.t1),
            const SizedBox(height: 2),
            Text('${t.artist} · ${t.album}', maxLines: 1, overflow: TextOverflow.ellipsis, style: MF.t3),
          ]),
        ),
        const SizedBox(width: 8),
        trailing ?? FormatPill(t.formatLabel),
      ]),
    );

/// Track actions sheet (screen 13).
Future<void> showTrackActions(BuildContext context, Track t, {VoidCallback? onRemove, String? removeLabel}) {
  return showMfSheet(context, (ctx) {
    void act(VoidCallback f) {
      Navigator.of(ctx).pop();
      f();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _sheetHeader(t),
        Group(children: [
          ListItem(
              icon: Icons.playlist_play_rounded,
              title: 'Play next',
              onTap: () => act(() {
                    playerController.playNext([t]);
                    toast('Playing next');
                  })),
          ListItem(
              icon: Icons.queue_rounded,
              title: 'Add to queue',
              onTap: () => act(() {
                    playerController.addToQueue([t]);
                    toast('Added to queue');
                  })),
          ListItem(
              icon: Icons.playlist_add_rounded,
              title: 'Add to playlist…',
              onTap: () => act(() => showAddToPlaylist(context, [t]))),
          ListenableBuilder(
            listenable: playlistStore,
            builder: (_, _) {
              final fav = playlistStore.isFavorite(t.key);
              return ListItem(
                icon: fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                title: fav ? 'Remove from Favorites' : 'Add to Favorites',
                onTap: () => playlistStore.toggleFavorite(t.key),
              );
            },
          ),
        ]),
        const SizedBox(height: 14),
        Group(children: [
          ListItem(icon: Icons.album_rounded, title: 'Go to album', onTap: () => act(() => AppNav.album(t.albumId))),
          ListItem(
              icon: Icons.person_rounded,
              title: 'Go to artist',
              onTap: () => act(() => AppNav.artist(t.albumArtist.isNotEmpty ? t.albumArtist : t.artist))),
          ListItem(icon: Icons.info_outline_rounded, title: 'Track info', onTap: () => act(() => showTrackInfo(context, t))),
          if (onRemove != null)
            ListItem(
                icon: Icons.remove_circle_outline_rounded,
                title: removeLabel ?? 'Remove',
                onTap: () => act(onRemove)),
        ]),
      ]),
    );
  });
}

/// Track info sheet (screen 14).
Future<void> showTrackInfo(BuildContext context, Track t) {
  return showMfSheet(context, (ctx) {
    final loc = [libraryStore.rootDisplayName(t.root), ...t.relDir.split('/').where((s) => s.isNotEmpty)].join(' › ');
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _sheetHeader(t),
        Group(children: [
          const KV('Format', 'FLAC (lossless)'),
          KV('Bit depth', '${t.bitDepth}-bit'),
          KV('Sample rate', '${formatKhz(t.sampleRate)} kHz'),
          KV('Channels', switch (t.channels) { 1 => 'Mono', 2 => 'Stereo', _ => '${t.channels} channels' }),
          KV('Bitrate', '${t.bitrateKbps} kbps'),
          KV('Duration', fmtDuration(t.duration)),
          KV('File size', fmtSize(t.size)),
          KV('Location', loc),
          KV('File', t.fileName),
        ]),
        const SectionLabel('Output'),
        _OutputCard(track: t),
      ]),
    );
  });
}

class _OutputCard extends StatelessWidget {
  const _OutputCard({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final listen = Listenable.merge(
        [playerController.output, playerController.matched, playerController.current, eqController]);
    return ListenableBuilder(
      listenable: listen,
      builder: (context, _) {
        final o = playerController.output.value;
        final isCur = playerController.current.value?.key == track.key;
        final kind = switch (o.kind) {
          OutputKind.usb => 'USB',
          OutputKind.bluetooth => 'Bluetooth',
          OutputKind.wired => 'Wired',
          OutputKind.speaker => 'Speaker',
          OutputKind.airplay => 'AirPlay',
          OutputKind.hdmi => 'HDMI',
          _ => 'Output',
        };
        final rate = o.sampleRate > 0 ? ' · ${formatKhz(o.sampleRate)} kHz' : '';
        final matched = playerController.matched.value;
        final String status;
        final IconData icon;
        if (!isCur) {
          status = 'Play this track to check the output path';
          icon = Icons.info_outline_rounded;
        } else if (matched) {
          status = 'Bit-perfect: matched';
          icon = Icons.check_circle_rounded;
        } else if (eqController.active) {
          status = 'Processed: EQ is on';
          icon = Icons.graphic_eq_rounded;
        } else if (o.kind == OutputKind.bluetooth) {
          status = 'Bluetooth re-encodes audio (not lossless)';
          icon = Icons.bluetooth_audio_rounded;
        } else {
          status = 'Resampled by the system';
          icon = Icons.sync_alt_rounded;
        }
        final src = '${track.bitDepth}/${formatKhz(track.sampleRate)}';
        final out = o.sampleRate > 0 ? formatKhz(o.sampleRate) : '?';
        return Group(children: [
          ListItem(
            icon: switch (o.kind) {
              OutputKind.usb => Icons.usb_rounded,
              OutputKind.bluetooth => Icons.bluetooth_audio_rounded,
              OutputKind.wired => Icons.headphones_rounded,
              _ => Icons.speaker_rounded,
            },
            title: o.deviceName,
            subtitle: '$kind$rate',
          ),
          ListItem(
            leading: Icon(icon, color: matched && isCur ? MF.text : MF.text2, size: 24),
            title: status,
            subtitle: isCur ? 'Source $src → output $out kHz · EQ ${eqController.active ? 'on' : 'off'}' : null,
          ),
        ]);
      },
    );
  }
}

/// Queue sheet (screen 12).
Future<void> showQueue(BuildContext context) {
  return showMfSheet(context, (ctx) => const _QueueSheet(), expand: true);
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final listen = Listenable.merge([
      playerController.queue,
      playerController.queueIndex,
      playerController.shuffle,
      playerController.repeat,
    ]);
    return ListenableBuilder(
      listenable: listen,
      builder: (context, _) {
        final q = playerController.queue.value;
        final idx = playerController.queueIndex.value;
        final shuffle = playerController.shuffle.value;
        final repeat = playerController.repeat.value;
        final cur = (idx >= 0 && idx < q.length) ? q[idx] : null;
        final upNext = idx + 1 < q.length ? q.sublist(idx + 1) : <Track>[];
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              const Expanded(child: Text('Queue', style: MF.h2)),
              RoundButton(
                icon: Icons.shuffle_rounded,
                label: shuffle ? 'Shuffle on' : 'Shuffle off',
                diameter: 40,
                iconSize: 20,
                color: shuffle ? MF.text : MF.text2,
                dot: shuffle,
                onTap: playerController.toggleShuffle,
              ),
              const SizedBox(width: 12),
              RoundButton(
                icon: repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                label: 'Repeat ${repeat.name}',
                diameter: 40,
                iconSize: 20,
                color: repeat == RepeatMode.off ? MF.text2 : MF.text,
                dot: repeat != RepeatMode.off,
                onTap: playerController.cycleRepeat,
              ),
            ]),
          ),
          if (cur != null) ...[
            const SectionLabel('Now playing', padding: EdgeInsets.fromLTRB(20, 4, 20, 6)),
            TrackRow(track: cur, onTap: () {}),
          ],
          SectionLabel(
            'Up next',
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            trailing: upNext.isEmpty
                ? null
                : GestureDetector(
                    onTap: () async {
                      for (var i = q.length - 1; i > idx; i--) {
                        await playerController.removeFromQueue(i);
                      }
                    },
                    child: const Text('Clear', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: MF.text3)),
                  ),
          ),
          if (upNext.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Text('Nothing queued after this track.', style: MF.t3),
            )
          else
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: upNext.length,
                onReorderItem: (from, to) {
                  if (from == to) return;
                  playerController.moveInQueue(idx + 1 + from, idx + 1 + to);
                },
                proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
                itemBuilder: (context, i) {
                  final t = upNext[i];
                  final pos = idx + 1 + i;
                  return Dismissible(
                    key: ValueKey('q$pos:${t.key}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      padding: const EdgeInsets.only(right: 24),
                      alignment: Alignment.centerRight,
                      decoration: BoxDecoration(color: MF.light, borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.remove_circle_outline_rounded, color: MF.bg),
                    ),
                    onDismissed: (_) => playerController.removeFromQueue(pos),
                    child: TrackRow(
                      track: t,
                      onTap: () => playerController.jumpTo(pos),
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
            ),
        ]);
      },
    );
  }
}

/// Add-to-playlist sheet (screen 11b).
Future<void> showAddToPlaylist(BuildContext context, List<Track> tracks) {
  final keys = [for (final t in tracks) t.key];
  return showMfSheet(context, (ctx) {
    return ListenableBuilder(
      listenable: playlistStore,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Text(tracks.length == 1 ? 'Add "${tracks.first.title}" to…' : 'Add ${tracks.length} songs to…',
                style: MF.t1, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Group(children: [
            ListItem(
              icon: Icons.add_rounded,
              title: 'New playlist…',
              onTap: () async {
                Navigator.of(ctx).pop();
                await createPlaylistFlow(context, keys: keys);
              },
            ),
            for (final p in playlistStore.playlists)
              ListItem(
                leading: Collage(tracks: playlistStore.tracksOf(p.id), size: 40, seed: p.name, favorites: p.isFavorites),
                title: p.name,
                subtitle: plural(playlistStore.playableCount(p.id), 'song'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final n = await playlistStore.addTracks(p.id, keys, skipDuplicates: true);
                  toast(n == 0 ? 'Already in "${p.name}"' : 'Added to "${p.name}"');
                },
              ),
          ]),
        ]),
      ),
    );
  });
}
