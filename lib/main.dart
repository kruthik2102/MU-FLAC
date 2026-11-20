// Placeholder debug app that exercises the backend API in lib/core/.
// The real UI (lib/ui/) replaces this file's widgets.
import 'package:material_ui/material_ui.dart';

import 'core/core.dart';

Future<void> main() async {
  await bootstrap();
  runApp(const DebugApp());
}

class DebugApp extends StatelessWidget {
  const DebugApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MU-FLAC',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const DebugHome(),
    );
  }
}

class DebugHome extends StatelessWidget {
  const DebugHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MU-FLAC (debug)'),
        actions: [
          IconButton(
            tooltip: 'Add folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => libraryStore.addRoot(),
          ),
          if (libraryStore.canImport)
            IconButton(
              tooltip: 'Import files',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => libraryStore.importFiles(),
            ),
          IconButton(
            tooltip: 'Rescan',
            icon: const Icon(Icons.refresh),
            onPressed: () => libraryStore.rescan(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: libraryStore,
        builder: (context, _) {
          final tracks = libraryStore.tracks;
          return Column(
            children: [
              if (libraryStore.needsPermission)
                ListTile(
                  title: const Text('Media permission needed'),
                  trailing: TextButton(
                    onPressed: libraryStore.requestPermission,
                    child: const Text('Grant'),
                  ),
                ),
              if (libraryStore.scanning)
                LinearProgressIndicator(
                    value: libraryStore.scanTotal == 0 ? null : libraryStore.progress),
              ListTile(
                dense: true,
                title: Text('${tracks.length} tracks · '
                    '${libraryStore.albums.length} albums · '
                    '${libraryStore.roots.length} roots'),
                subtitle: Text([
                  libraryStore.scanStatus,
                  if (libraryStore.notDownloadedCount > 0)
                    '${libraryStore.notDownloadedCount} not downloaded',
                ].where((s) => s.isNotEmpty).join(' · ')),
                trailing: TextButton(
                  onPressed: tracks.isEmpty
                      ? null
                      : () => playerController.playTracks(tracks, shuffle: true),
                  child: const Text('Shuffle all'),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) {
                    final t = tracks[i];
                    return ListTile(
                      dense: true,
                      title: Text(t.title, maxLines: 1),
                      subtitle: Text('${t.artist} · ${t.album} · ${t.formatLabel}',
                          maxLines: 1),
                      onTap: () => playerController.playTracks(tracks, index: i),
                    );
                  },
                ),
              ),
              const _MiniPlayer(),
            ],
          );
        },
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Track?>(
      valueListenable: playerController.current,
      builder: (context, track, _) {
        if (track == null) return const SizedBox.shrink();
        return Material(
          elevation: 4,
          child: ListTile(
            title: Text(track.title, maxLines: 1),
            subtitle: ValueListenableBuilder<OutputInfo>(
              valueListenable: playerController.output,
              builder: (context, out, _) => ValueListenableBuilder<bool>(
                valueListenable: playerController.matched,
                builder: (context, matched, _) => Text(
                  '${track.formatLabel} → ${out.deviceName} '
                  '${out.sampleRate} Hz${matched ? ' (matched)' : ''}',
                  maxLines: 1,
                ),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: playerController.previous,
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: playerController.playing,
                  builder: (context, playing, _) => IconButton(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: playerController.togglePlay,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: playerController.next,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
