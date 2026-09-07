import Flutter
import UIKit

/// Native iOS tab host for Cinematy.
///
/// The important detail is that this is a real UITabBarController. On iOS 26+
/// UIKit gives UITabBarController the system Liquid Glass tab-bar appearance.
/// Flutter stays as one persistent child above the tab controller's content,
/// while the native tab bar remains owned & rendered by UIKit.
final class CinematyNativeTabBarHostController: UITabBarController, UITabBarControllerDelegate {
  private let flutterController: FlutterViewController
  private var channel: FlutterMethodChannel?
  private var compact = false
  private var installedFlutterView = false

  init(flutterController: FlutterViewController) {
    self.flutterController = flutterController
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .black
    delegate = self

    configureSystemTabBar()
    configureTabs()
    installFlutterContentIfNeeded()
    installChannel()

    // Visible by default. Flutter may hide it only while a pushed route such
    // as details/player is on top. This prevents a channel timing issue from
    // ever leaving the main tab bar invisible.
    tabBar.isHidden = false
    tabBar.isUserInteractionEnabled = true
    tabBar.alpha = 1
    view.bringSubviewToFront(tabBar)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // Flutter can create/resize platform surfaces during rotation. Always keep
    // UIKit's system tab bar as the top-most sibling.
    view.bringSubviewToFront(tabBar)
  }

  private func configureSystemTabBar() {
    tabBar.isTranslucent = true
    tabBar.backgroundColor = nil
    tabBar.barTintColor = nil
    tabBar.backgroundImage = nil
    tabBar.shadowImage = nil
    tabBar.tintColor = UIColor(red: 0.96, green: 0.07, blue: 0.11, alpha: 1)
    tabBar.unselectedItemTintColor = UIColor.secondaryLabel.withAlphaComponent(0.72)
    tabBar.semanticContentAttribute = .forceRightToLeft
    tabBar.accessibilityIdentifier = "cinematy.native.liquid.tabbar"

    // Deliberately DO NOT install a custom UITabBarAppearance background.
    // UIKit's default appearance is what enables the native Liquid Glass
    // treatment when the app runs on a system that supports it.
  }

  private func configureTabs() {
    let definitions: [(String, String, String)] = [
      ("الرئيسية", "house", "house.fill"),
      ("اكتشف", "safari", "safari.fill"),
      ("البحث", "magnifyingglass", "magnifyingglass"),
      ("مكتبتي", "rectangle.stack", "rectangle.stack.fill"),
    ]

    let controllers: [UIViewController] = definitions.enumerated().map { index, definition in
      let controller = UIViewController()
      controller.view.backgroundColor = .clear
      controller.tabBarItem = UITabBarItem(
        title: definition.0,
        image: UIImage(systemName: definition.1),
        selectedImage: UIImage(systemName: definition.2)
      )
      controller.tabBarItem.tag = index
      return controller
    }

    setViewControllers(controllers, animated: false)
    selectedIndex = 0
  }

  private func installFlutterContentIfNeeded() {
    guard !installedFlutterView else { return }
    installedFlutterView = true

    // Flutter is not one of the managed tab controllers. It is a persistent
    // content child, while the native UITabBarController owns only selection
    // chrome. Changing a tab therefore keeps one Flutter engine/state alive.
    addChild(flutterController)
    flutterController.view.translatesAutoresizingMaskIntoConstraints = false
    view.insertSubview(flutterController.view, belowSubview: tabBar)
    NSLayoutConstraint.activate([
      flutterController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      flutterController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      flutterController.view.topAnchor.constraint(equalTo: view.topAnchor),
      flutterController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    flutterController.didMove(toParent: self)
  }

  private func installChannel() {
    let methodChannel = FlutterMethodChannel(
      name: "cinematy/native_tab_bar",
      binaryMessenger: flutterController.binaryMessenger
    )

    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "native_tab_bar_gone", message: nil, details: nil))
        return
      }

      switch call.method {
      case "ping":
        result(true)

      case "setIndex":
        self.setSelectedIndex(Self.intValue(call.arguments) ?? 0)
        result(nil)

      case "setVisible":
        self.setBarVisible(Self.boolValue(call.arguments) ?? true, animated: true)
        result(nil)

      case "setCompact":
        self.setCompact(Self.boolValue(call.arguments) ?? false, animated: true)
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    channel = methodChannel
  }

  func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
    let index = tabBarController.selectedIndex
    channel?.invokeMethod("tabChanged", arguments: index)
    view.bringSubviewToFront(tabBar)
  }

  private func setSelectedIndex(_ rawIndex: Int) {
    guard let controllers = viewControllers, !controllers.isEmpty else { return }
    let index = min(max(rawIndex, 0), controllers.count - 1)
    if selectedIndex != index {
      selectedIndex = index
    }
    view.bringSubviewToFront(tabBar)
  }

  private func setBarVisible(_ visible: Bool, animated: Bool) {
    guard tabBar.isHidden == visible else {
      if visible {
        tabBar.isHidden = false
        tabBar.isUserInteractionEnabled = true
        tabBar.alpha = 0
        view.bringSubviewToFront(tabBar)
      }

      let changes = {
        self.tabBar.alpha = visible ? 1 : 0
      }

      let completion: (Bool) -> Void = { _ in
        self.tabBar.isHidden = !visible
        self.tabBar.isUserInteractionEnabled = visible
        if visible {
          self.tabBar.alpha = 1
          self.view.bringSubviewToFront(self.tabBar)
        }
      }

      if animated {
        UIView.animate(
          withDuration: 0.22,
          delay: 0,
          options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
          animations: changes,
          completion: completion
        )
      } else {
        changes()
        completion(true)
      }
      return
    }

    if visible {
      tabBar.alpha = 1
      tabBar.isUserInteractionEnabled = true
      view.bringSubviewToFront(tabBar)
    }
  }

  private func setCompact(_ value: Bool, animated: Bool) {
    guard value != compact else { return }
    compact = value

    // On iOS 26+ the controller itself owns the modern tab bar. We keep this
    // tiny scale only as the explicit Cinematy scroll response requested by
    // the app, without replacing or drawing over the system glass material.
    let changes = {
      self.tabBar.transform = value
        ? CGAffineTransform(scaleX: 0.90, y: 0.90)
        : .identity
    }

    guard animated else {
      changes()
      return
    }

    UIView.animate(
      withDuration: 0.30,
      delay: 0,
      usingSpringWithDamping: 0.86,
      initialSpringVelocity: 0.18,
      options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
      animations: changes
    )
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

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var nativeTabHost: CinematyNativeTabBarHostController?
  private var installAttempt = 0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    installNativeTabHostWhenReady()
    return launched
  }

  private func installNativeTabHostWhenReady() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard self.nativeTabHost == nil else { return }

      guard let window = self.window,
            let flutterController = Self.findFlutterController(in: window.rootViewController) else {
        self.installAttempt += 1
        if self.installAttempt < 80 {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.installNativeTabHostWhenReady()
          }
        } else {
          print("[CinematyTabBar] ERROR: FlutterViewController was not found; native tab host not installed")
        }
        return
      }

      self.installAttempt = 0
      let host = CinematyNativeTabBarHostController(flutterController: flutterController)
      self.nativeTabHost = host
      window.rootViewController = host
      window.makeKeyAndVisible()
      host.loadViewIfNeeded()
      print("[CinematyTabBar] Native UITabBarController installed")
    }
  }

  private static func findFlutterController(in controller: UIViewController?) -> FlutterViewController? {
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
}
