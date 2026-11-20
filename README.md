# MU-FLAC

An offline FLAC music player for Android and iPhone, built with Flutter.

MU-FLAC plays your own `.flac` files. It has no streaming, no accounts and no network code. The Android release build doesn't even request the INTERNET permission.

## Features

- **FLAC only, read with our own parser.** A pure-Dart metadata reader handles STREAMINFO, Vorbis comments and embedded cover art, and copes with files that start with an ID3 tag.
- **Browse by albums, artists, songs, or folders.** You can play a whole folder recursively.
- **Gapless queue.** Shuffle, repeat (off / all / one), play next, add to queue, remove, reorder and seek. The last queue is restored on launch.
- **Background playback.** Lock-screen, notification and headset-button controls.
- **Playlists.** Create, rename, delete and reorder your own playlists, plus a built-in **Favorites** (the heart button).
- **Matched output.** On iPhone the hardware sample rate follows each track, so a USB-C DAC (for example Moondrop CHU II DSP) runs at the file's native rate. The app shows the output device, its current rate, and a "matched" badge when the rates agree and the EQ is off.
- **10-band EQ.** Bands at 31 Hz to 16 kHz, ±12 dB each, with a preamp and named presets. When the EQ is off, the audio path is untouched. Android 9+ only for now; on iPhone the EQ is shown as unsupported.
- **System volume slider** (Android).
- **Album art comes only from the embedded picture.** No downloads. Albums without art get a generated colour gradient.

## Install

### Android

1. Download `MU-FLAC.apk` from the [Releases](../../releases) page on your phone.
2. Open it. Allow "Install unknown apps" for your browser or file manager if asked.
3. Open MU-FLAC, allow access to music, and add the folder(s) that hold your FLAC files.

Updates install over the old version because every release is signed with the same key.

### iPhone (sideload)

The release contains an **unsigned** `MU-FLAC.ipa`. Sign and install it with your own Apple ID:

- **Sideloadly** (Windows/macOS): connect the iPhone, drag `MU-FLAC.ipa` in, enter your Apple ID, then press Start.
- **AltStore**: My Apps → `+` → choose `MU-FLAC.ipa`.

Then on the iPhone, go to Settings → General → VPN & Device Management and trust your Apple ID. Turn on Developer Mode if iOS asks.

With a free Apple ID the app expires after **7 days** and must be re-signed. AltStore can refresh it automatically. Re-signing keeps your library, playlists and folders because the bundle id stays `com.kr.muFlac`.

## Adding music

### Android

Go to Settings → Music folders → **Add folder** and pick any folder, for example `Music`. MU-FLAC scans it, including sub-folders, for `.flac` files. You can add several folders and remove them later.

### iPhone

There are three ways, and you can combine them:

1. **On My iPhone → MU-FLAC** (always available).
   - From a Windows PC: open the **Apple Devices** app → your iPhone → **Files** → **MU-FLAC**, then drag in files or folders.
   - On a Mac: Finder → your iPhone → Files → MU-FLAC.
   - On the phone: Files app → On My iPhone → MU-FLAC.
2. **Pick a folder in the Files app.** In MU-FLAC go to Settings → Music folders → **Add folder** and choose any folder you can see in Files, for example a folder in On My iPhone. You can change or remove it later. MU-FLAC remembers the folder across restarts and re-signs.
3. **Import files.** Pick `.flac` files in Files and MU-FLAC copies them into its own folder.

iCloud Drive files that aren't downloaded to the phone are skipped, because MU-FLAC never uses the network. The app tells you how many there are. Download them in the Files app first ("Download Now" or "Keep Downloaded").

The library rescans incrementally, checking file size and modification time, so only new or changed files are re-read.

## Offline promise

- No network code anywhere in the app.
- The Android release manifest removes `INTERNET` with `tools:node="remove"`. CI fails the build if the APK asks for it.
- Album art comes only from the picture embedded in each file.

## Build from source

Requirements: Flutter **3.50.1** (stable). Android builds also need JDK 17+ and the Android SDK. iOS builds need Xcode on macOS.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release                 # Android (universal APK)
flutter build ios --release --no-codesign   # iOS, then zip Runner.app into Payload/
```

Release signing (Android): create `android/key.properties`:

```properties
storePassword=...
keyPassword=...
keyAlias=muflac
storeFile=upload.p12
storeType=pkcs12
```

Put the keystore at `android/app/upload.p12`. Both files are gitignored. Without them, release builds are signed with the debug key.

CI (`.github/workflows/release.yml`) runs analyze and tests, then builds the APK and the unsigned IPA. When you push a `v*` tag it publishes both to a GitHub Release. The workflow needs two secrets:

- `ANDROID_KEYSTORE_B64`: the keystore, base64-encoded
- `ANDROID_KEYSTORE_PASSWORD`: the keystore password

## Project layout

```
lib/core/      backend: FLAC parser, library, playlists, player, EQ, volume
lib/ui/        screens
lib/main.dart  entry point (calls bootstrap())
android/       MainActivity.kt: output info, DynamicsProcessing EQ, volume
ios/           AppDelegate.swift: preferred sample rate, output info, folder bookmarks
test/          parser, library/folder, playlist, queue-order and EQ tests
```
