import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Native UIKit tab bar. We deliberately use UITabBar itself instead of
    // painting a Flutter imitation, so newer iOS releases can provide their
    // native system material / Liquid Glass appearance automatically.
    if let registrar = self.registrar(forPlugin: "CinematyNativeTabBar") {
      let factory = CinematyNativeTabBarFactory(messenger: registrar.messenger())
      registrar.register(factory, withId: "cinematy/native_tab_bar")
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

final class CinematyNativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
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
    CinematyNativeTabBarView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      arguments: args
    )
  }
}

final class CinematyNativeTabBarView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let rootView: UIView
  private let tabBar: UITabBar
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    arguments: Any?
  ) {
    rootView = UIView(frame: frame)
    tabBar = UITabBar(frame: .zero)
    channel = FlutterMethodChannel(
      name: "cinematy/native_tab_bar_\(viewId)",
      binaryMessenger: messenger
    )

    super.init()

    rootView.backgroundColor = .clear
    rootView.isOpaque = false
    rootView.semanticContentAttribute = .forceRightToLeft

    tabBar.translatesAutoresizingMaskIntoConstraints = false
    tabBar.delegate = self
    tabBar.semanticContentAttribute = .forceRightToLeft
    tabBar.tintColor = UIColor(red: 1.0, green: 0.278, blue: 0.239, alpha: 1.0)
    tabBar.unselectedItemTintColor = UIColor.secondaryLabel.withAlphaComponent(0.68)
    tabBar.itemPositioning = .fill

    let items = [
      makeItem(title: "الرئيسية", normal: "house", selected: "house.fill", tag: 0),
      makeItem(title: "اكتشف", normal: "safari", selected: "safari.fill", tag: 1),
      makeItem(title: "البحث", normal: "magnifyingglass", selected: "magnifyingglass", tag: 2),
      makeItem(title: "مكتبتي", normal: "rectangle.stack", selected: "rectangle.stack.fill", tag: 3),
    ]
    tabBar.items = items

    // We only customize item colors; the background/material remains UIKit's
    // native tab-bar rendering rather than a hand-made blur.
    let appearance = UITabBarAppearance()
    appearance.configureWithDefaultBackground()

    let red = UIColor(red: 1.0, green: 0.278, blue: 0.239, alpha: 1.0)
    let selectedAttributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: red,
      .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
    ]
    let normalAttributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: UIColor.secondaryLabel.withAlphaComponent(0.72),
      .font: UIFont.systemFont(ofSize: 10, weight: .medium),
    ]

    for layout in [
      appearance.stackedLayoutAppearance,
      appearance.inlineLayoutAppearance,
      appearance.compactInlineLayoutAppearance,
    ] {
      layout.selected.iconColor = red
      layout.selected.titleTextAttributes = selectedAttributes
      layout.normal.iconColor = UIColor.secondaryLabel.withAlphaComponent(0.72)
      layout.normal.titleTextAttributes = normalAttributes
    }

    tabBar.standardAppearance = appearance
    if #available(iOS 15.0, *) {
      tabBar.scrollEdgeAppearance = appearance
    }

    rootView.addSubview(tabBar)
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: rootView.topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])

    let initialIndex = (arguments as? [String: Any])?["index"] as? Int ?? 0
    setSelectedIndex(initialIndex)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "setIndex":
        if let index = call.arguments as? Int {
          self.setSelectedIndex(index)
        } else if let number = call.arguments as? NSNumber {
          self.setSelectedIndex(number.intValue)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    rootView
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("tabChanged", arguments: item.tag)
  }

  private func setSelectedIndex(_ index: Int) {
    guard let items = tabBar.items, items.indices.contains(index) else { return }
    if tabBar.selectedItem !== items[index] {
      tabBar.selectedItem = items[index]
    }
  }

  private func makeItem(
    title: String,
    normal: String,
    selected: String,
    tag: Int
  ) -> UITabBarItem {
    UITabBarItem(
      title: title,
      image: UIImage(systemName: normal),
      selectedImage: UIImage(systemName: selected)
    ).withTag(tag)
  }
}

private extension UITabBarItem {
  func withTag(_ value: Int) -> UITabBarItem {
    tag = value
    return self
  }
}
