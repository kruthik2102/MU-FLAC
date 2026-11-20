import 'package:material_ui/material_ui.dart';

import '../core/core.dart';
import 'shell.dart';
import 'theme.dart';
import 'widgets.dart';

/// Folders root (screens 08a/08b): the configured music sources.
class FoldersTab extends StatelessWidget {
  const FoldersTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: libraryStore,
        builder: (context, _) {
          final roots = libraryStore.roots;
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Text('Folders', style: MF.h1),
            ),
            const SectionLabel('Sources'),
            Group(children: [
              for (final r in roots)
                ListItem(
                  icon: r.kind == RootKind.docs ? Icons.phone_iphone_rounded : Icons.folder_rounded,
                  title: r.displayName,
                  subtitle: r.available
                      ? '${r.locationLabel} · ${plural(libraryStore.tracksUnder(r.id, '').length, 'track')}'
                      : 'Not available - reconnect or choose it again',
                  chevron: r.available,
                  onTap: r.available
                      ? () => Navigator.of(context).push(mfRoute(FolderPage(rootId: r.id, relDir: '')))
                      : null,
                ),
              if (libraryStore.canAddRoots)
                ListItem(icon: Icons.add_rounded, title: 'Choose folder…', onTap: pickMusicFolder),
            ]),
            if (roots.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(28, 16, 28, 0),
                child: Text('No music folders yet. Choose the folder that holds your FLAC files.', style: MF.t3),
              ),
          ]);
        },
      ),
    );
  }
}

/// Folder contents (screen 08c).
class FolderPage extends StatelessWidget {
  const FolderPage({super.key, required this.rootId, required this.relDir});
  final String rootId;
  final String relDir;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MF.bg,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: libraryStore,
          builder: (context, _) {
            final l = libraryStore.listFolder(rootId, relDir);
            final all = libraryStore.tracksUnder(rootId, relDir);
            final crumbs = [libraryStore.rootDisplayName(rootId), ...relDir.split('/').where((s) => s.isNotEmpty)];
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              PageTop(title: l.name.isEmpty ? libraryStore.rootDisplayName(rootId) : l.name),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
                child: Text(crumbs.join('  ›  '),
                    style: MF.t3, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              if (all.isNotEmpty) PlayShuffleRow(tracks: all, playLabel: 'Play folder'),
              if (l.folders.isNotEmpty) ...[
                const SectionLabel('Folders'),
                Group(children: [
                  for (final f in l.folders)
                    ListItem(
                      icon: Icons.folder_rounded,
                      title: f.name,
                      subtitle: plural(f.trackCount, 'track'),
                      chevron: true,
                      onTap: () => Navigator.of(context).push(mfRoute(FolderPage(rootId: f.rootId, relDir: f.relDir))),
                    ),
                ]),
              ],
              if (l.tracks.isNotEmpty) ...[
                const SectionLabel('Files', padding: EdgeInsets.fromLTRB(20, 24, 20, 6)),
                for (var i = 0; i < l.tracks.length; i++)
                  TrackRow(track: l.tracks[i], onTap: () => playerController.playTracks(l.tracks, index: i)),
              ],
              if (l.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: EmptyHint(icon: Icons.folder_off_rounded, title: 'No FLAC files here'),
                ),
            ]);
          },
        ),
      ),
    );
  }
}
