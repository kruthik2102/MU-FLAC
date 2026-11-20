import AVFoundation
import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Native side of the `mu_flac/audio` channel; kept alive for the app lifetime.
  private var audioNative: MuFlacAudioNative?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MuFlacAudioNative") {
      audioNative = MuFlacAudioNative(registrar: registrar)
    }
  }
}

/// A folder picked in the Files app whose security-scoped access is running.
private struct ActiveFolder {
  let url: URL
  let started: Bool
}

/// `mu_flac/audio` MethodChannel + `mu_flac/audio_events` EventChannel.
///
/// - setPreferredSampleRate: match the hardware rate to the track (USB DACs).
/// - outputInfo: current route name / kind / hardware sample rate.
/// - pickFolder / resolveFolders / releaseFolder: user-picked music folders
///   via security-scoped bookmarks (bookmark data is persisted by Dart).
/// - EQ and volume are not supported on iOS (Dart reports unsupported).
final class MuFlacAudioNative: NSObject, FlutterStreamHandler, UIDocumentPickerDelegate {
  private let registrar: FlutterPluginRegistrar
  private let channel: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var eventSink: FlutterEventSink?
  private var pendingPick: FlutterResult?
  private var activeFolders: [String: ActiveFolder] = [:]

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    self.channel = FlutterMethodChannel(
      name: "mu_flac/audio", binaryMessenger: registrar.messenger())
    self.events = FlutterEventChannel(
      name: "mu_flac/audio_events", binaryMessenger: registrar.messenger())
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result: result)
    }
    events.setStreamHandler(self)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(routeChanged(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Events

  @objc private func routeChanged(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(["event": "outputChanged"])
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - Method calls

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "setPreferredSampleRate":
      let rate = (args["sampleRate"] as? NSNumber)?.doubleValue ?? 0
      result(setPreferredSampleRate(rate))
    case "outputInfo":
      result(outputInfo())
    case "sdkInt":
      result(0)
    case "eqSupported", "eqApply":
      result(false)
    case "getVolume", "setVolume":
      result(nil)
    case "pickFolder":
      pickFolder(result: result)
    case "resolveFolders":
      let items = args["items"] as? [[String: Any]] ?? []
      result(resolveFolders(items))
    case "releaseFolder":
      releaseFolder(args["id"] as? String ?? "")
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Sample rate / output

  /// Asks the hardware to run at the track's rate (bit-perfect to USB DACs).
  /// Returns the hardware sample rate after the request.
  private func setPreferredSampleRate(_ rate: Double) -> Double {
    let session = AVAudioSession.sharedInstance()
    guard rate > 0 else { return session.sampleRate }
    do {
      try session.setPreferredSampleRate(rate)
    } catch {
      NSLog("MU-FLAC: setPreferredSampleRate(\(rate)) failed: \(error.localizedDescription)")
    }
    return session.sampleRate
  }

  private func outputInfo() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    let output = session.currentRoute.outputs.first
    var kind = "unknown"
    if let portType = output?.portType {
      switch portType {
      case .usbAudio:
        kind = "usb"
      case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
        kind = "bluetooth"
      case .headphones, .lineOut:
        kind = "wired"
      case .builtInSpeaker, .builtInReceiver:
        kind = "speaker"
      case .airPlay:
        kind = "airplay"
      case .HDMI:
        kind = "hdmi"
      default:
        kind = "other"
      }
    }
    return [
      "name": output?.portName ?? "",
      "kind": kind,
      "sampleRate": session.sampleRate,
    ]
  }

  // MARK: - Folder bookmarks

  private func topViewController() -> UIViewController? {
    var root: UIViewController? = registrar.viewController
    if root == nil {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let windows = scenes.flatMap { $0.windows }
      root = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    }
    while let presented = root?.presentedViewController {
      root = presented
    }
    return root
  }

  private func pickFolder(result: @escaping FlutterResult) {
    if pendingPick != nil {
      result(FlutterError(code: "busy", message: "Folder picker already open", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "no_ui", message: "No view controller to present from", details: nil))
      return
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    pendingPick = result
    presenter.present(picker, animated: true, completion: nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pendingPick else { return }
    pendingPick = nil
    guard let url = urls.first else {
      result(nil)
      return
    }
    let started = url.startAccessingSecurityScopedResource()
    do {
      let data = try url.bookmarkData(
        options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
      let id = UUID().uuidString
      // Keep access running for the app lifetime (released by releaseFolder).
      activeFolders[id] = ActiveFolder(url: url, started: started)
      result([
        "id": id,
        "displayName": url.lastPathComponent,
        "path": url.path,
        "bookmark": data.base64EncodedString(),
      ])
    } catch {
      if started {
        url.stopAccessingSecurityScopedResource()
      }
      result(FlutterError(code: "bookmark_failed", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pendingPick
    pendingPick = nil
    result?(nil)
  }

  /// Resolves bookmarks saved by Dart and starts access. Paths can change
  /// between launches, so the id (not the path) is the identity.
  private func resolveFolders(_ items: [[String: Any]]) -> [String: Any] {
    var out: [String: Any] = [:]
    for item in items {
      guard let id = item["id"] as? String else { continue }
      if let active = activeFolders[id] {
        out[id] = [
          "ok": true,
          "path": active.url.path,
          "displayName": active.url.lastPathComponent,
        ]
        continue
      }
      guard let b64 = item["bookmark"] as? String, let data = Data(base64Encoded: b64) else {
        out[id] = ["ok": false, "error": "bad bookmark"]
        continue
      }
      var stale = false
      do {
        let url = try URL(
          resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        let started = url.startAccessingSecurityScopedResource()
        var entry: [String: Any] = [
          "ok": true,
          "path": url.path,
          "displayName": url.lastPathComponent,
        ]
        if stale {
          if let fresh = try? url.bookmarkData(
            options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
          {
            entry["bookmark"] = fresh.base64EncodedString()
          }
        }
        activeFolders[id] = ActiveFolder(url: url, started: started)
        out[id] = entry
      } catch {
        out[id] = ["ok": false, "error": error.localizedDescription]
      }
    }
    return out
  }

  private func releaseFolder(_ id: String) {
    guard let active = activeFolders.removeValue(forKey: id) else { return }
    if active.started {
      active.url.stopAccessingSecurityScopedResource()
    }
  }
}
