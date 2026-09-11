import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
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
  private var frameProbeTimer: Timer?
  private var videoOutput: AVPlayerItemVideoOutput?
  private var didTryHlsForCurrentURL = false
  private var currentItemGeneration = 0

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

    if AVPictureInPictureController.isPictureInPictureSupported(),
       let controller = AVPictureInPictureController(playerLayer: container.playerLayer) {
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
    frameProbeTimer?.invalidate()
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
    didTryHlsForCurrentURL = false
    currentItemGeneration += 1
    fallbackWorkItem?.cancel()
    frameProbeTimer?.invalidate()
    itemStatusObservation?.invalidate()

    guard let url = URL(string: urlString) else { return }
    let item = makePlayerItem(url: url)
    observe(item, originalURL: urlString, generation: currentItemGeneration)
    player.replaceCurrentItem(with: item)
    player.play()
  }

  private func makePlayerItem(url: URL) -> AVPlayerItem {
    let asset = AVURLAsset(url: url)
    let item = AVPlayerItem(asset: asset)

    // Keep a video output attached so we can verify that iOS is actually
    // producing decoded video frames. This catches the common IPTV case in
    // which AVPlayer reports readyToPlay and audio works, but an HEVC video
    // track inside a raw MPEG-TS never produces a visible frame.
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    ])
    item.add(output)
    videoOutput = output

    item.preferredForwardBufferDuration = 2.0
    item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
    return item
  }

  private func observe(_ item: AVPlayerItem, originalURL: String, generation: Int) {
    itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      guard let self, generation == self.currentItemGeneration else { return }

      if item.status == .failed {
        self.tryHlsFallback(originalURL)
        return
      }

      if item.status == .readyToPlay {
        self.startDecodedFrameProbe(for: item, originalURL: originalURL, generation: generation)
      }
    }

    // Some Xtream panels expose both .ts and .m3u8 but AVPlayer may remain in
    // unknown state for a raw transport stream. Try the HLS form only when the
    // first item never becomes ready; successful direct playback is untouched.
    let work = DispatchWorkItem { [weak self, weak item] in
      guard let self, let item,
            generation == self.currentItemGeneration,
            self.currentURL == originalURL else { return }
      if item.status != .readyToPlay {
        self.tryHlsFallback(originalURL)
      }
    }
    fallbackWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: work)
  }

  private func startDecodedFrameProbe(
    for item: AVPlayerItem,
    originalURL: String,
    generation: Int
  ) {
    frameProbeTimer?.invalidate()

    let tracks = item.asset.tracks(withMediaType: .video)
    let hasVideoTrack = !tracks.isEmpty
    let isHEVC = tracks.contains(where: isHevcTrack)
    let isRawTransportStream = isTransportStreamURL(originalURL)

    // A normal H.264/HLS item that exposes video is already on the happy path.
    // Probe HEVC explicitly, and also probe raw TS streams because some panels
    // hide the codec details even though the symptom is still audio-only.
    guard isHEVC || isRawTransportStream || !hasVideoTrack else { return }

    var attempts = 0
    let maxAttempts = 14 // ~3.5 seconds after readyToPlay.
    frameProbeTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self, weak item] timer in
      guard let self, let item,
            generation == self.currentItemGeneration,
            self.currentURL == originalURL else {
        timer.invalidate()
        return
      }

      attempts += 1
      if let output = self.videoOutput {
        let time = self.player.currentTime()
        if output.hasNewPixelBuffer(forItemTime: time) {
          timer.invalidate()
          return
        }
      }

      if attempts >= maxAttempts {
        timer.invalidate()
        // If AVPlayer has audio/ready state but no decoded video frames, the
        // HLS rendition is often the same HEVC stream packaged in the form iOS
        // expects. Switching packaging is lossless: no transcoding and no
        // quality reduction.
        self.tryHlsFallback(originalURL, forceForAudioOnlyVideo: true)
      }
    }
  }

  private func isHevcTrack(_ track: AVAssetTrack) -> Bool {
    for case let description as CMFormatDescription in track.formatDescriptions {
      let subtype = CMFormatDescriptionGetMediaSubType(description)
      if subtype == kCMVideoCodecType_HEVC || subtype == fourCC("hev1") {
        return true
      }
    }
    return false
  }

  private func fourCC(_ value: String) -> FourCharCode {
    var result: FourCharCode = 0
    for scalar in value.unicodeScalars.prefix(4) {
      result = (result << 8) + FourCharCode(scalar.value)
    }
    return result
  }

  private func isTransportStreamURL(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString) else { return false }
    return url.pathExtension.lowercased() == "ts"
  }

  private func hlsVariant(of urlString: String) -> String? {
    guard var components = URLComponents(string: urlString) else { return nil }
    let path = components.path
    guard (path as NSString).pathExtension.lowercased() == "ts" else { return nil }
    components.path = (path as NSString).deletingPathExtension + ".m3u8"
    return components.string
  }

  private func tryHlsFallback(_ originalURL: String, forceForAudioOnlyVideo: Bool = false) {
    guard currentItemGeneration > 0,
          currentURL == originalURL || forceForAudioOnlyVideo,
          !didTryHlsForCurrentURL,
          let hls = hlsVariant(of: originalURL) else { return }

    didTryHlsForCurrentURL = true
    currentURL = hls
    currentItemGeneration += 1
    let generation = currentItemGeneration
    fallbackWorkItem?.cancel()
    frameProbeTimer?.invalidate()
    itemStatusObservation?.invalidate()

    guard let url = URL(string: hls) else { return }
    let item = makePlayerItem(url: url)
    observe(item, originalURL: hls, generation: generation)
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
