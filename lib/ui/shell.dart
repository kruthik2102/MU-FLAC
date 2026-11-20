import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/core.dart';
import 'folders.dart';
import 'library.dart';
import 'now_playing.dart';
import 'playlists.dart';
import 'settings.dart';
import 'theme.dart';
import 'widgets.dart';

final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

/// Cross-screen navigation (used from sheets and Now Playing).
abstract final class AppNav {
  static _HomeShellState? _shell;

  static void _toTab(int i) {
    rootNavKey.currentState?.popUntil((r) => r.isFirst);
    _shell?._select(i, popToRoot: true);
  }

  static void _push(int tab, Widget page) {
    _toTab(tab);
    _shell?._navKeys[tab].currentState?.push(mfRoute(page));
  }

  static void library() => _toTab(0);
  static void settings() => _toTab(3);
  static void album(String id) => _push(0, AlbumPage(albumId: id));
  static void artist(String name) => _push(0, ArtistPage(name: name));
  static void nowPlaying() {
    final nav = rootNavKey.currentState;
    if (nav == null || !playerController.hasQueue) return;
    nav.push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => const NowPlayingPage(),
      transitionsBuilder: (_, a, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ));
  }
}

Route<T> mfRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, a, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: ColoredBox(color: MF.bg, child: child),
      ),
    );

class MuFlacApp extends StatelessWidget {
  const MuFlacApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: MF.panel,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    return MaterialApp(
      title: 'MU-FLAC',
      debugShowCheckedModeBanner: false,
      theme: MF.theme(),
      darkTheme: MF.theme(),
      themeMode: ThemeMode.dark,
      navigatorKey: rootNavKey,
      scaffoldMessengerKey: messengerKey,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _navKeys = List.generate(4, (_) => GlobalKey<NavigatorState>());

  static const _tabs = [
    (Icons.library_music_rounded, 'Library'),
    (Icons.folder_rounded, 'Folders'),
    (Icons.queue_music_rounded, 'Playlists'),
    (Icons.settings_rounded, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    AppNav._shell = this;
  }

  @override
  void dispose() {
    if (AppNav._shell == this) AppNav._shell = null;
    super.dispose();
  }

  void _select(int i, {bool popToRoot = false}) {
    if (i == _tab || popToRoot) {
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
    }
    if (i != _tab) setState(() => _tab = i);
  }

  Widget _root(int i) => switch (i) {
        0 => const LibraryTab(),
        1 => const FoldersTab(),
        2 => const PlaylistsTab(),
        _ => const SettingsTab(),
      };

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _navKeys[_tab].currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (_tab != 0) {
          setState(() => _tab = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: MF.bg,
        body: Column(children: [
          Expanded(
            child: IndexedStack(index: _tab, children: [
              for (var i = 0; i < 4; i++)
                HeroControllerScope.none(
                  child: Navigator(
                    key: _navKeys[i],
                    onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _root(i)),
                  ),
                ),
            ]),
          ),
          const MiniPlayer(),
          Container(
            height: 58 + bottom,
            padding: EdgeInsets.only(bottom: bottom, left: 12, right: 12, top: 6),
            decoration: const BoxDecoration(
              color: MF.panel,
              border: Border(top: BorderSide(color: Color(0x0DFFFFFF))),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: Semantics(
                    selected: i == _tab,
                    button: true,
                    label: _tabs[i].$2,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _select(i),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_tabs[i].$1, size: 24, color: i == _tab ? MF.text : MF.text2),
                        const SizedBox(height: 4),
                        Text(_tabs[i].$2,
                            style: MF.tabLabel.copyWith(color: i == _tab ? MF.text : MF.text2)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Track?>(
      valueListenable: playerController.current,
      builder: (context, t, _) {
        if (t == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: GestureDetector(
            onTap: AppNav.nowPlaying,
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -200) AppNav.nowPlaying();
            },
            child: Container(
              height: 64,
              padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
              decoration: BoxDecoration(
                  color: MF.mini, borderRadius: BorderRadius.circular(20), boxShadow: MF.miniShadow),
              child: Row(children: [
                CoverArt(path: t.artPath, seed: t.album, size: 44, radius: 9),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: MF.t2.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: MF.t3),
                  ]),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: playerController.playing,
                  builder: (_, playing, _) => RoundButton(
                    icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    label: playing ? 'Pause' : 'Play',
                    diameter: 40,
                    iconSize: 24,
                    onTap: playerController.togglePlay,
                  ),
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: playerController.next,
                  icon: const Icon(Icons.skip_next_rounded, color: MF.text, size: 26),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// First-run / empty library state (screens 17a/17b).
class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: libraryStore,
      builder: (context, _) {
        final ios = libraryStore.isIOS;
        if (libraryStore.scanning) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Scanning your music…', style: MF.t1),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                      value: libraryStore.progress > 0 ? libraryStore.progress : null, minHeight: 4),
                ),
                const SizedBox(height: 10),
                Text(libraryStore.scanStatus, style: MF.t3, textAlign: TextAlign.center),
              ]),
            ),
          );
        }
        return SingleChildScrollView(
          child: Column(children: [
            const SizedBox(height: 24),
            EmptyHint(
              icon: Icons.graphic_eq_rounded,
              title: 'Your FLAC library,\nfully offline',
              body: ios
                  ? 'Pick a folder in the Files app (On My iPhone, iCloud Drive or a USB drive). MU-FLAC reads your music where it is - nothing is uploaded, ever.'
                  : 'Choose the folder where your FLAC files live. MU-FLAC never connects to the internet.',
              action: Column(children: [
                if (libraryStore.needsPermission) ...[
                  PillButton(
                    label: 'Allow access to music',
                    icon: Icons.lock_open_rounded,
                    primary: true,
                    onTap: () async {
                      final ok = await libraryStore.requestPermission();
                      if (!ok && await libraryStore.permissionPermanentlyDenied()) {
                        toast('Permission denied - enable "Music and audio" for MU-FLAC in Android settings');
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                PillButton(
                  label: 'Choose music folder…',
                  icon: Icons.create_new_folder_rounded,
                  primary: !libraryStore.needsPermission,
                  onTap: () => pickMusicFolder(),
                ),
                if (ios) ...[
                  const SizedBox(height: 14),
                  PillButton(label: 'Import files', icon: Icons.file_download_outlined, onTap: importMusicFiles),
                ],
              ]),
            ),
            if (ios)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                child: Text(
                  'From a Windows PC: open the Apple Devices app → your iPhone → Files → MU-FLAC, and drop FLAC files in.',
                  style: MF.t3.copyWith(height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ),
          ]),
        );
      },
    );
  }
}

Future<void> pickMusicFolder() async {
  try {
    final r = await libraryStore.addRoot();
    if (r != null) toast('Added ${r.displayName} - scanning…');
  } catch (e) {
    toast('Could not open that folder: $e');
  }
}

Future<void> importMusicFiles() async {
  try {
    final n = await libraryStore.importFiles();
    if (n > 0) toast('Imported ${plural(n, 'file')}');
  } catch (e) {
    toast('Import failed: $e');
  }
}
