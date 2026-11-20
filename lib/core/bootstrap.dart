import 'package:flutter/widgets.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app_paths.dart';
import 'eq_controller.dart';
import 'library_store.dart';
import 'player_controller.dart';
import 'playlist_store.dart';
import 'settings_store.dart';
import 'volume_controller.dart';

bool _booted = false;

/// Initializes every backend singleton. Call once from `main()` before
/// `runApp`. The library rescan continues in the background afterwards
/// (watch `libraryStore.scanning` / `progress`).
Future<void> bootstrap() async {
  if (_booted) return;
  _booted = true;
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.kr.mu_flac.channel.player',
    androidNotificationChannelName: 'Now playing',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );
  await AppPaths.init();
  await settingsStore.load();
  await playlistStore.load();
  await eqController.init();
  await volumeController.init();
  libraryStore.onRootsMerged = playlistStore.remapKeyPrefixes;
  await libraryStore.init();
  await playerController.init();
}
