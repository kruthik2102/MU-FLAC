import 'package:material_ui/material_ui.dart';

import '../core/core.dart';
import 'eq.dart';
import 'shell.dart';
import 'theme.dart';
import 'widgets.dart';

/// Settings (screens 16a/16b).
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final listen = Listenable.merge([libraryStore, eqController, playerController.output]);
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: listen,
        builder: (context, _) {
          final lib = libraryStore;
          final ios = lib.isIOS;
          final out = playerController.output.value;
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Text('Settings', style: MF.h1),
            ),
            if (lib.needsPermission) ...[
              const SizedBox(height: 16),
              Group(children: [
                ListItem(
                  icon: Icons.lock_open_rounded,
                  title: 'Allow access to music',
                  subtitle: 'MU-FLAC needs the "Music and audio" permission to read your folders.',
                  chevron: true,
                  onTap: () async {
                    final ok = await lib.requestPermission();
                    if (!ok && await lib.permissionPermanentlyDenied()) {
                      toast('Enable "Music and audio" for MU-FLAC in Android settings');
                    }
                  },
                ),
              ]),
            ],
            const SectionLabel('Music folders'),
            Group(children: [
              for (final r in lib.roots)
                ListItem(
                  icon: r.kind == RootKind.docs ? Icons.phone_iphone_rounded : Icons.folder_rounded,
                  title: r.kind == RootKind.docs ? '${r.displayName} (Default)' : r.displayName,
                  subtitle: r.available
                      ? '${r.locationLabel} · ${plural(lib.tracksUnder(r.id, '').length, 'track')}'
                      : 'Not available - choose it again',
                  trailing: r.removable
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          GestureDetector(
                            onTap: () => _change(r),
                            child: const FormatPill('Change', grey: true),
                          ),
                          IconButton(
                            tooltip: 'Remove ${r.displayName}',
                            icon: const Icon(Icons.close_rounded, color: MF.text2, size: 20),
                            onPressed: () => _remove(context, r),
                          ),
                        ])
                      : null,
                ),
              if (lib.canAddRoots)
                ListItem(
                  icon: Icons.create_new_folder_rounded,
                  title: 'Choose folder…',
                  subtitle: ios ? 'Opens the Files app' : 'Opens the folder picker',
                  onTap: pickMusicFolder,
                ),
              if (lib.canImport)
                ListItem(
                  icon: Icons.file_download_outlined,
                  title: 'Import files',
                  subtitle: 'Copies FLAC files into On My iPhone › MU-FLAC',
                  onTap: importMusicFiles,
                ),
            ]),
            if (ios)
              const Padding(
                padding: EdgeInsets.fromLTRB(28, 10, 28, 0),
                child: Text(
                  'Copy from a PC: Apple Devices app → your iPhone → Files → MU-FLAC.',
                  style: MF.meta,
                ),
              ),
            if (lib.notDownloadedCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 10, 28, 0),
                child: Text(
                  '${plural(lib.notDownloadedCount, 'file')} not downloaded from iCloud: download them in the Files app first.',
                  style: MF.meta.copyWith(color: MF.text3),
                ),
              ),
            const SectionLabel('Library'),
            Group(children: [
              ListItem(
                icon: Icons.refresh_rounded,
                title: lib.scanning ? 'Scanning…' : 'Rescan library',
                subtitle: lib.scanning ? lib.scanStatus : 'Looks for new, changed and removed files',
                trailing: lib.scanning
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: MF.text2, value: lib.progress > 0 ? lib.progress : null),
                      )
                    : null,
                onTap: lib.scanning ? null : () => lib.rescan(),
              ),
              KV('Songs', '${lib.tracks.length}'),
              KV('Albums', '${lib.albums.length}'),
              KV('Artists', '${lib.artists.length}'),
              if (lib.unreadableCount > 0) KV('Unreadable files', '${lib.unreadableCount}'),
            ]),
            const SectionLabel('Audio'),
            Group(children: [
              ListItem(
                icon: Icons.graphic_eq_rounded,
                title: 'Equalizer',
                subtitle: !eqController.supported
                    ? 'Not available on this device yet'
                    : eqController.enabled
                        ? 'On - audio is processed'
                        : 'Off - bit-perfect',
                chevron: true,
                onTap: () => Navigator.of(context).push(mfRoute(const EqualizerPage())),
              ),
              KV('Output', '${out.deviceName}${out.sampleRate > 0 ? ' · ${formatKhz(out.sampleRate)} kHz' : ''}'),
              KV('Sample-rate matching', ios ? 'On (per track)' : 'System mixer'),
              const KV('Gapless playback', 'On'),
            ]),
            const SectionLabel('About'),
            const Group(children: [
              KV('Version', kAppVersion),
              KV('Network', '100% offline - no internet permission'),
              KV('Formats', 'FLAC (up to 32-bit / 384 kHz)'),
            ]),
          ]);
        },
      ),
    );
  }

  Future<void> _change(LibraryRoot old) async {
    final r = await libraryStore.addRoot();
    if (r != null && r.id != old.id) {
      await libraryStore.removeRoot(old.id);
      toast('Switched to ${r.displayName}');
    }
  }

  Future<void> _remove(BuildContext context, LibraryRoot r) async {
    final ok = await confirmDialog(context,
        title: 'Remove "${r.displayName}"?',
        body: 'Its songs leave your library. Your files are not deleted.',
        action: 'Remove');
    if (ok) await libraryStore.removeRoot(r.id);
  }
}
