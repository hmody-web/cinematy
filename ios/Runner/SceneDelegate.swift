import Flutter
import UIKit

/// Cinematy's iOS system tab bar host.
///
/// Flutter 3.41+ uses UIScene by default, so all UI/window work must live here,
/// not in AppDelegate. Keeping FlutterViewController as the scene root preserves
/// Flutter's scene lifecycle while the native UITabBar is layered above it.
final class SceneDelegate: FlutterSceneDelegate, UITabBarDelegate {
  private var nativeTabBar: UITabBar?
  private var nativeChannel: FlutterMethodChannel?
  private var installAttempt = 0
  private var isCompact = false

  private let selectedRed = UIColor(
    red: 0.96,
    green: 0.06,
    blue: 0.10,
    alpha: 1.0
  )

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // The Main storyboard/root FlutterViewController can finish attaching at
    // the end of this callback. Install on the next main-loop turn and retry
    // briefly instead of ever failing silently.
    installNativeTabBarWhenReady(in: scene)
  }

  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    keepNativeTabBarOnTop(in: scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    keepNativeTabBarOnTop(in: scene)
  }

  private func installNativeTabBarWhenReady(in scene: UIScene) {
    DispatchQueue.main.async { [weak self, weak scene] in
      guard let self, let scene else { return }
      guard self.nativeTabBar == nil else {
        self.keepNativeTabBarOnTop(in: scene)
        return
      }

      guard let flutterController = self.findFlutterController(in: scene) else {
        self.installAttempt += 1
        if self.installAttempt < 120 {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak scene] in
            guard let self, let scene else { return }
            self.installNativeTabBarWhenReady(in: scene)
          }
        } else {
          print("[CinematyTabBar] ERROR: FlutterViewController not found in UIScene")
        }
        return
      }

      self.installAttempt = 0
      self.installNativeTabBar(on: flutterController)
    }
  }

  private func findFlutterController(in scene: UIScene) -> FlutterViewController? {
    guard let windowScene = scene as? UIWindowScene else { return nil }

    if let root = window?.rootViewController,
       let flutter = findFlutterController(in: root) {
      return flutter
    }

    for candidateWindow in windowScene.windows {
      if let flutter = findFlutterController(in: candidateWindow.rootViewController) {
        return flutter
      }
    }
    return nil
  }

  private func findFlutterController(in controller: UIViewController?) -> FlutterViewController? {
    guard let controller else { return nil }
    if let flutter = controller as? FlutterViewController { return flutter }

    if let navigation = controller as? UINavigationController {
      for child in navigation.viewControllers {
        if let flutter = findFlutterController(in: child) { return flutter }
      }
    }

    if let tab = controller as? UITabBarController {
      for child in tab.viewControllers ?? [] {
        if let flutter = findFlutterController(in: child) { return flutter }
      }
    }

    for child in controller.children {
      if let flutter = findFlutterController(in: child) { return flutter }
    }
    return nil
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
    tabBar.tintColor = selectedRed
    tabBar.unselectedItemTintColor = UIColor.secondaryLabel.withAlphaComponent(0.72)
    tabBar.accessibilityIdentifier = "cinematy.native.scene.liquid.tabbar"
    tabBar.layer.zPosition = 100_000

    // Do not assign UITabBarAppearance/backgroundEffect/backgroundImage.
    // The system owns the material. On iOS versions with Liquid Glass this
    // is the real UIKit material, not a Flutter blur imitation.
    tabBar.backgroundColor = nil
    tabBar.barTintColor = nil
    tabBar.backgroundImage = nil
    tabBar.shadowImage = nil

    let items = [
      makeItem(title: "الرئيسية", normal: "house", selected: "house.fill", tag: 0),
      makeItem(title: "اكتشف", normal: "safari", selected: "safari.fill", tag: 1),
      makeItem(title: "البحث", normal: "magnifyingglass", selected: "magnifyingglass", tag: 2),
      makeItem(title: "التلفاز", normal: "tv", selected: "tv.fill", tag: 3),
      makeItem(title: "مكتبتي", normal: "rectangle.stack", selected: "rectangle.stack.fill", tag: 4),
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
    tabBar.selectedItem = items.first

    controller.view.addSubview(tabBar)

    // UIKit's standard content region is 49 pt. Extending from safe-area
    // bottom to the physical bottom includes the Home Indicator correctly.
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
      tabBar.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
      tabBar.topAnchor.constraint(
        equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor,
        constant: -49
      ),
    ])

    // Visible immediately. Flutter may later hide it only when a pushed route
    // is above the main shell. This removes channel-startup timing as a cause
    // of an invisible main tab bar.
    tabBar.isHidden = false
    tabBar.isUserInteractionEnabled = true
    tabBar.alpha = 1.0
    controller.view.bringSubviewToFront(tabBar)

    let channel = FlutterMethodChannel(
      name: "cinematy/native_tab_bar",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self, weak controller] call, result in
      guard let self, let tabBar = self.nativeTabBar else {
        result(FlutterError(
          code: "native_tab_bar_unavailable",
          message: "The UIScene native tab bar has not been installed yet.",
          details: nil
        ))
        return
      }

      switch call.method {
      case "ping":
        result(true)

      case "setIndex":
        self.setSelectedIndex(Self.intValue(call.arguments) ?? 0)
        result(nil)

      case "setCompact":
        self.setCompact(Self.boolValue(call.arguments) ?? false, animated: true)
        result(nil)

      case "setVisible":
        let visible = Self.boolValue(call.arguments) ?? true
        self.setVisible(visible, tabBar: tabBar, controller: controller, animated: true)
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    nativeTabBar = tabBar
    nativeChannel = channel

    print("[CinematyTabBar] UIScene native UITabBar installed")
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    nativeChannel?.invokeMethod("tabChanged", arguments: item.tag)
  }

  private func setSelectedIndex(_ rawIndex: Int) {
    guard let tabBar = nativeTabBar,
          let items = tabBar.items,
          !items.isEmpty else { return }

    let index = min(max(rawIndex, 0), items.count - 1)
    tabBar.selectedItem = items[index]
  }

  private func setVisible(
    _ visible: Bool,
    tabBar: UITabBar,
    controller: FlutterViewController?,
    animated: Bool
  ) {
    if visible {
      tabBar.isHidden = false
      tabBar.isUserInteractionEnabled = true
      controller?.view.bringSubviewToFront(tabBar)
    }

    let changes = {
      tabBar.alpha = visible ? 1.0 : 0.0
    }

    let completion: (Bool) -> Void = { _ in
      tabBar.isHidden = !visible
      tabBar.isUserInteractionEnabled = visible
      if visible {
        tabBar.alpha = 1.0
        controller?.view.bringSubviewToFront(tabBar)
      }
    }

    if animated {
      UIView.animate(
        withDuration: 0.20,
        delay: 0,
        options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
        animations: changes,
        completion: completion
      )
    } else {
      changes()
      completion(true)
    }
  }

  private func setCompact(_ compact: Bool, animated: Bool) {
    guard let tabBar = nativeTabBar else { return }
    guard compact != isCompact else { return }
    isCompact = compact

    let changes = {
      tabBar.transform = compact
        ? CGAffineTransform(scaleX: 0.90, y: 0.90)
        : .identity
    }

    if animated {
      UIView.animate(
        withDuration: 0.30,
        delay: 0,
        usingSpringWithDamping: 0.86,
        initialSpringVelocity: 0.16,
        options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
        animations: changes
      )
    } else {
      changes()
    }
  }

  private func keepNativeTabBarOnTop(in scene: UIScene) {
    guard let tabBar = nativeTabBar,
          let controller = findFlutterController(in: scene) else { return }
    controller.view.bringSubviewToFront(tabBar)
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
      switch value.lowercased() {
      case "true", "1", "yes": return true
      case "false", "0", "no": return false
      default: return nil
      }
    }
    return nil
  }
}
