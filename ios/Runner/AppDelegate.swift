import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, UITabBarDelegate {
  private var nativeTabBar: UITabBar?
  private var nativeTabBarChannel: FlutterMethodChannel?
  private var installAttempt = 0
  private var isCompact = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    // Install after Flutter's root view exists. If the storyboard/controller is
    // still being attached, retry briefly on the main queue instead of silently
    // ending up with an invisible tab bar.
    installNativeTabBarWhenReady()
    return launched
  }

  private func installNativeTabBarWhenReady() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if self.nativeTabBar != nil { return }

      guard let controller = self.window?.rootViewController as? FlutterViewController else {
        self.installAttempt += 1
        guard self.installAttempt < 40 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
          self?.installNativeTabBarWhenReady()
        }
        return
      }

      self.installAttempt = 0
      self.installNativeTabBar(on: controller)
    }
  }

  private func installNativeTabBar(on controller: FlutterViewController) {
    guard nativeTabBar == nil else { return }

    let tabBar = UITabBar(frame: .zero)
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    tabBar.delegate = self
    tabBar.isTranslucent = true
    tabBar.clipsToBounds = false
    tabBar.itemPositioning = .fill
    tabBar.semanticContentAttribute = .forceRightToLeft
    tabBar.tintColor = UIColor(red: 0.96, green: 0.08, blue: 0.12, alpha: 1.0)
    tabBar.unselectedItemTintColor = UIColor.secondaryLabel.withAlphaComponent(0.74)
    tabBar.layer.zPosition = 9_999
    tabBar.accessibilityIdentifier = "cinematy.native.tabbar"

    // Do not paint a custom background or blur here. UIKit owns the bar's
    // native material, so iOS versions that provide Liquid Glass render their
    // real system style rather than a Flutter imitation.

    let items = [
      makeItem(title: "الرئيسية", normal: "house", selected: "house.fill", tag: 0),
      makeItem(title: "اكتشف", normal: "safari", selected: "safari.fill", tag: 1),
      makeItem(title: "البحث", normal: "magnifyingglass", selected: "magnifyingglass", tag: 2),
      makeItem(title: "مكتبتي", normal: "rectangle.stack", selected: "rectangle.stack.fill", tag: 3),
    ]

    let selectedRed = UIColor(red: 0.96, green: 0.08, blue: 0.12, alpha: 1.0)
    let normalAttributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: UIColor.secondaryLabel.withAlphaComponent(0.74),
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
    tabBar.selectedItem = items[0]

    controller.view.addSubview(tabBar)

    // 49 pt is UIKit's standard tab-bar content height. Pinning its top to
    // safeArea.bottom - 49 and its bottom to the physical screen bottom makes
    // the bar automatically include the home-indicator area on every iPhone.
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
      tabBar.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
      tabBar.topAnchor.constraint(
        equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor,
        constant: -49
      ),
    ])

    controller.view.bringSubviewToFront(tabBar)

    // Stay hidden until the Flutter shell explicitly attaches. This prevents
    // the native bar from covering splash/routes before CinematyShell is ready.
    tabBar.isHidden = true
    tabBar.isUserInteractionEnabled = false

    let channel = FlutterMethodChannel(
      name: "cinematy/native_tab_bar",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self, weak controller] call, result in
      guard let self, let tabBar = self.nativeTabBar else {
        result(FlutterError(
          code: "native_tab_bar_unavailable",
          message: "Native tab bar is not installed yet.",
          details: nil
        ))
        return
      }

      switch call.method {
      case "ping":
        result(true)

      case "setIndex":
        let index = Self.intValue(call.arguments)
        self.setSelectedIndex(index ?? 0)
        result(nil)

      case "setCompact":
        let compact = Self.boolValue(call.arguments)
        self.setCompact(compact ?? false, animated: true)
        result(nil)

      case "setVisible":
        let visible = Self.boolValue(call.arguments) ?? false
        tabBar.isHidden = !visible
        tabBar.isUserInteractionEnabled = visible
        if visible {
          tabBar.alpha = 1.0
          if let rootView = controller?.view {
            rootView.bringSubviewToFront(tabBar)
          }
        }
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    nativeTabBar = tabBar
    nativeTabBarChannel = channel
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    nativeTabBarChannel?.invokeMethod("tabChanged", arguments: item.tag)
  }

  private func setSelectedIndex(_ index: Int) {
    guard let tabBar = nativeTabBar,
          let items = tabBar.items,
          items.indices.contains(index) else { return }
    tabBar.selectedItem = items[index]
  }

  private func setCompact(_ compact: Bool, animated: Bool) {
    guard let tabBar = nativeTabBar else { return }
    guard compact != isCompact || !animated else { return }
    isCompact = compact

    let changes = {
      tabBar.transform = compact
        ? CGAffineTransform(scaleX: 0.90, y: 0.90)
        : .identity
      tabBar.alpha = compact ? 0.97 : 1.0
    }

    guard animated else {
      changes()
      return
    }

    UIView.animate(
      withDuration: 0.32,
      delay: 0,
      usingSpringWithDamping: 0.84,
      initialSpringVelocity: 0.18,
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

  private static func intValue(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    if let value = value as? Int { return value }
    if let value = value as? String { return Int(value) }
    return nil
  }

  private static func boolValue(_ value: Any?) -> Bool? {
    if let number = value as? NSNumber { return number.boolValue }
    if let value = value as? Bool { return value }
    if let value = value as? String {
      if value == "true" || value == "1" { return true }
      if value == "false" || value == "0" { return false }
    }
    return nil
  }
}
