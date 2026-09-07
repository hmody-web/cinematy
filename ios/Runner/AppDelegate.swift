import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register the UIKit view BEFORE Flutter tries to create UiKitView.
    // This is a real UITabBar; Flutter only reserves its layout slot.
    if let registrar = self.registrar(forPlugin: "CinematyNativeTabBarPlugin") {
      registrar.register(
        CinematyNativeTabBarFactory(messenger: registrar.messenger()),
        withId: "cinematy/native_tab_bar"
      )
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class CinematyNativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    CinematyNativeTabBarPlatformView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      arguments: args
    )
  }
}

private final class CinematyNativeTabBarPlatformView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let container: UIView
  private let tabBar: UITabBar
  private let channel: FlutterMethodChannel
  private var isCompact = false

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    arguments: Any?
  ) {
    container = UIView(frame: frame)
    tabBar = UITabBar(frame: .zero)
    channel = FlutterMethodChannel(
      name: "cinematy/native_tab_bar_\(viewId)",
      binaryMessenger: messenger
    )

    super.init()

    container.backgroundColor = .clear
    container.isOpaque = false
    container.clipsToBounds = false

    tabBar.translatesAutoresizingMaskIntoConstraints = false
    tabBar.delegate = self
    tabBar.isTranslucent = true
    tabBar.clipsToBounds = false
    tabBar.itemPositioning = .fill
    tabBar.semanticContentAttribute = .forceRightToLeft

    // Keep UIKit's native background/material completely untouched.
    // On modern iOS this lets the system provide its own Liquid Glass style.
    let selectedRed = UIColor(red: 0.96, green: 0.11, blue: 0.14, alpha: 1.0)
    tabBar.tintColor = selectedRed
    tabBar.unselectedItemTintColor = UIColor.secondaryLabel.withAlphaComponent(0.72)

    let items = [
      makeItem(title: "الرئيسية", normal: "house", selected: "house.fill", tag: 0),
      makeItem(title: "اكتشف", normal: "safari", selected: "safari.fill", tag: 1),
      makeItem(title: "البحث", normal: "magnifyingglass", selected: "magnifyingglass", tag: 2),
      makeItem(title: "مكتبتي", normal: "rectangle.stack", selected: "rectangle.stack.fill", tag: 3),
    ]

    let normalAttributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: UIColor.secondaryLabel.withAlphaComponent(0.72),
      .font: UIFont.systemFont(ofSize: 10, weight: .medium),
    ]
    let selectedAttributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: selectedRed,
      .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
    ]

    for item in items {
      item.setTitleTextAttributes(normalAttributes, for: .normal)
      item.setTitleTextAttributes(selectedAttributes, for: .selected)
    }
    tabBar.items = items

    container.addSubview(tabBar)
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: container.topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    let params = arguments as? [String: Any]
    let initialIndex = (params?["index"] as? NSNumber)?.intValue ?? 0
    let initialCompact = (params?["compact"] as? NSNumber)?.boolValue ?? false
    setSelectedIndex(initialIndex)
    setCompact(initialCompact, animated: false)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }

      switch call.method {
      case "setIndex":
        if let number = call.arguments as? NSNumber {
          self.setSelectedIndex(number.intValue)
        } else if let index = call.arguments as? Int {
          self.setSelectedIndex(index)
        }
        result(nil)

      case "setCompact":
        let compact: Bool
        if let number = call.arguments as? NSNumber {
          compact = number.boolValue
        } else {
          compact = call.arguments as? Bool ?? false
        }
        self.setCompact(compact, animated: true)
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    container
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("tabChanged", arguments: item.tag)
  }

  private func setSelectedIndex(_ index: Int) {
    guard let items = tabBar.items, items.indices.contains(index) else { return }
    tabBar.selectedItem = items[index]
  }

  private func setCompact(_ compact: Bool, animated: Bool) {
    guard compact != isCompact || !animated else { return }
    isCompact = compact

    let changes = {
      self.tabBar.transform = compact
        ? CGAffineTransform(scaleX: 0.90, y: 0.90)
        : .identity
      self.tabBar.alpha = compact ? 0.97 : 1.0
    }

    guard animated else {
      changes()
      return
    }

    UIView.animate(
      withDuration: 0.34,
      delay: 0,
      usingSpringWithDamping: 0.82,
      initialSpringVelocity: 0.20,
      options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
      animations: changes
    )
  }

  private func makeItem(
    title: String,
    normal: String,
    selected: String,
    tag: Int
  ) -> UITabBarItem {
    let item = UITabBarItem(
      title: title,
      image: UIImage(systemName: normal),
      selectedImage: UIImage(systemName: selected)
    )
    item.tag = tag
    return item
  }
}
