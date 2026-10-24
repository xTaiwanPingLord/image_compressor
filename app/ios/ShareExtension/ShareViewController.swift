import UIKit
import UniformTypeIdentifiers

/// Share Extension: copies the shared images into the App Group inbox and opens the app.
///
/// Inbox layout: <group>/Inbox/<batch>/<index>/<file name>; a batch is written as
/// "<batch>.part" and renamed when complete so the app never reads half a batch.
/// The app also checks the inbox whenever it becomes active, so opening it by hand
/// works if the URL hand-off below is refused by the system.
final class ShareViewController: UIViewController {
  static let appGroup = "group.tw.toast.imageCompressor"
  static let openURL = URL(string: "imgcompressor://shared")!
  /// Darwin notification the app listens for (it may already be on screen, e.g. iPad Split View)
  static let inboxNotification = "tw.toast.imageCompressor.inbox"

  private var started = false

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !started else { return }
    started = true
    collect()
  }

  private func collect() {
    let fm = FileManager.default
    guard let root = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) else {
      return finish()
    }
    let id = "\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(8))"
    let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
    let part = inbox.appendingPathComponent(id + ".part", isDirectory: true)
    try? fm.createDirectory(at: part, withIntermediateDirectories: true)

    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    let group = DispatchGroup()
    for (i, p) in providers.enumerated() {
      guard
        let type = p.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true })
      else { continue }
      group.enter()
      p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
        defer { group.leave() }
        guard let url else { return }
        let ext = UTType(type)?.preferredFilenameExtension ?? url.pathExtension
        var name = p.suggestedName ?? url.deletingPathExtension().lastPathComponent
        if (name as NSString).pathExtension.isEmpty { name += "." + ext }
        let dir = part.appendingPathComponent(String(format: "%04d", i), isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // The provider deletes its file when this callback returns
        try? fm.copyItem(at: url, to: dir.appendingPathComponent(name))
      }
    }
    group.notify(queue: .main) {
      try? fm.moveItem(at: part, to: inbox.appendingPathComponent(id, isDirectory: true))
      CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(Self.inboxNotification as CFString), nil, nil, true)
      self.openHostApp()
      self.finish()
    }
  }

  /// UIApplication.open is unavailable to extensions; reach it through the responder chain.
  private func openHostApp() {
    let sel = NSSelectorFromString("openURL:options:completionHandler:")
    var r: UIResponder? = self
    while let x = r {
      if let app = x as? UIApplication, app.responds(to: sel) {
        typealias Open = @convention(c) (NSObject, Selector, URL, [String: Any], ((Bool) -> Void)?) -> Void
        let f = unsafeBitCast(app.method(for: sel), to: Open.self)
        f(app, sel, Self.openURL, [:], nil)
        return
      }
      r = x.next
    }
  }

  private func finish() {
    extensionContext?.completeRequest(returningItems: nil)
  }
}
