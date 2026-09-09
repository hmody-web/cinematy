import AVFoundation
import AVKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configurePlaybackAudioSession()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CinematyTvNativePlayer") {
      registrar.register(
        CinematyTvPlayerFactory(messenger: registrar.messenger()),
        withId: "cinematy/tv_native_player"
      )
    }
  }

  private func configurePlaybackAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback, options: [])
      try session.setActive(true)
    } catch {
      // Playback can still start; AVPlayer will retry audio-session activation.
    }
  }
}

private final class CinematyTvPlayerContainerView: UIView {
  let playerLayer = AVPlayerLayer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    playerLayer.videoGravity = .resizeAspect
    layer.addSublayer(playerLayer)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    playerLayer.frame = bounds
    CATransaction.commit()
  }
}

private final class CinematyTvPlayerFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    CinematyTvPlayerView(
      frame: frame,
      viewId: viewId,
      args: args as? [String: Any],
      messenger: messenger
    )
  }
}

private final class CinematyTvPlayerView: NSObject, FlutterPlatformView, AVPictureInPictureControllerDelegate {
  private let container: CinematyTvPlayerContainerView
  private let player = AVPlayer()
  private var pipController: AVPictureInPictureController?
  private var channel: FlutterMethodChannel?
  private var currentURL: String = ""
  private var fallbackWorkItem: DispatchWorkItem?
  private var itemStatusObservation: NSKeyValueObservation?

  init(
    frame: CGRect,
    viewId: Int64,
    args: [String: Any]?,
    messenger: FlutterBinaryMessenger
  ) {
    container = CinematyTvPlayerContainerView(frame: frame)
    super.init()

    container.playerLayer.player = player
    player.actionAtItemEnd = .none
    player.automaticallyWaitsToMinimizeStalling = true

    if AVPictureInPictureController.isPictureInPictureSupported() {
      let controller = AVPictureInPictureController(playerLayer: container.playerLayer)
      controller.delegate = self
      if #available(iOS 14.2, *) {
        controller.canStartPictureInPictureAutomaticallyFromInline = true
      }
      pipController = controller
    }

    let methodChannel = FlutterMethodChannel(
      name: "cinematy/tv_native_player/\(viewId)",
      binaryMessenger: messenger
    )
    channel = methodChannel
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "open":
        guard
          let body = call.arguments as? [String: Any],
          let url = body["url"] as? String
        else {
          result(FlutterError(code: "bad_url", message: "Missing URL", details: nil))
          return
        }
        self.open(url)
        result(nil)
      case "play":
        self.player.play()
        result(nil)
      case "pause":
        self.player.pause()
        result(nil)
      case "startPiP":
        self.startPictureInPicture()
        result(nil)
      case "stopPiP":
        self.pipController?.stopPictureInPicture()
        result(nil)
      case "isPiPSupported":
        result(AVPictureInPictureController.isPictureInPictureSupported())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    if let url = args?["url"] as? String {
      open(url)
    }
  }

  deinit {
    fallbackWorkItem?.cancel()
    itemStatusObservation?.invalidate()
    channel?.setMethodCallHandler(nil)
    player.pause()
    player.replaceCurrentItem(with: nil)
  }

  func view() -> UIView {
    container
  }

  private func open(_ urlString: String) {
    currentURL = urlString
    fallbackWorkItem?.cancel()
    itemStatusObservation?.invalidate()

    guard let url = URL(string: urlString) else { return }
    let item = AVPlayerItem(url: url)
    observe(item, originalURL: urlString)
    player.replaceCurrentItem(with: item)
    player.play()
  }

  private func observe(_ item: AVPlayerItem, originalURL: String) {
    itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      guard let self else { return }
      if item.status == .failed {
        self.tryHlsFallback(originalURL)
      }
    }

    // Some Xtream panels expose both .ts and .m3u8 but AVPlayer may remain in
    // unknown state for a raw transport stream. Try the HLS form only when the
    // first item never becomes ready; successful .ts playback is untouched.
    let work = DispatchWorkItem { [weak self, weak item] in
      guard let self, let item, self.currentURL == originalURL else { return }
      if item.status != .readyToPlay {
        self.tryHlsFallback(originalURL)
      }
    }
    fallbackWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: work)
  }

  private func tryHlsFallback(_ originalURL: String) {
    guard currentURL == originalURL, originalURL.lowercased().hasSuffix(".ts") else { return }
    let hls = String(originalURL.dropLast(3)) + ".m3u8"
    currentURL = hls
    fallbackWorkItem?.cancel()
    itemStatusObservation?.invalidate()
    guard let url = URL(string: hls) else { return }
    let item = AVPlayerItem(url: url)
    player.replaceCurrentItem(with: item)
    player.play()
  }

  private func startPictureInPicture() {
    guard let controller = pipController,
          AVPictureInPictureController.isPictureInPictureSupported(),
          !controller.isPictureInPictureActive
    else { return }

    if controller.isPictureInPicturePossible {
      controller.startPictureInPicture()
    } else {
      // Give AVPlayerLayer one frame to become PiP-eligible when the user exits
      // immediately after opening a channel.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak controller] in
        guard let controller,
              controller.isPictureInPicturePossible,
              !controller.isPictureInPictureActive
        else { return }
        controller.startPictureInPicture()
      }
    }
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(true)
  }
}
