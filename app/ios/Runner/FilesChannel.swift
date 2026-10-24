import Flutter
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// iOS file access for the Flutter side (channel "imgc/files"), same protocol as
/// Android's FilesChannel.kt so lib/platform/android_files.dart works unchanged.
///
/// The Rust core works on plain paths, so picked images are copied into tmp/imgc/import,
/// Rust writes outputs to tmp/imgc/export, and they are copied back into the user's folder.
/// Folders are kept as security-scoped bookmarks: tree = "iosbm:<base64 bookmark>".
final class FilesChannel: NSObject, UIDocumentPickerDelegate, PHPickerViewControllerDelegate {
  static let imageExts: Set<String> = [
    "jpg", "jpeg", "png", "webp", "bmp", "tif", "tiff", "gif", "heic", "heif", "hif",
  ]
  static let treePrefix = "iosbm:"
  /// 與 ShareExtension 共用的 App Group（Inbox 放分享進來的圖片）
  static let appGroup = "group.tw.toast.imageCompressor"
  /// ShareExtension 寫完 Inbox 後發出的 Darwin 通知（App 已在畫面上時不會觸發 didBecomeActive）
  static let inboxNotification = "tw.toast.imageCompressor.inbox"

  static func isImageName(_ name: String) -> Bool {
    imageExts.contains((name as NSString).pathExtension.lowercased())
  }

  private enum Kind { case images, folder }

  private let channel: FlutterMethodChannel
  private let fm = FileManager.default
  private let root: URL
  private let io = DispatchQueue(label: "imgc.files")
  private var importSeq = 0
  private var pending: FlutterResult?
  private var pendingKind = Kind.images
  var pendingShared: [[String: Any]]?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "imgc/files", binaryMessenger: messenger)
    root = FileManager.default.temporaryDirectory.appendingPathComponent("imgc", isDirectory: true)
    super.init()
    // Leftovers from the previous session
    try? fm.removeItem(at: root)
    try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    // Share Extension 寫入 Inbox 後會用 imgcompressor:// 開啟 App；也在每次回到前景時檢查
    NotificationCenter.default.addObserver(
      self, selector: #selector(pullInbox), name: UIApplication.didBecomeActiveNotification, object: nil)
    // iPad 分割畫面 / Slide Over：App 一直在前景，改由 extension 的 Darwin 通知觸發
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      { _, observer, _, _, _ in
        guard let observer else { return }
        Unmanaged<FilesChannel>.fromOpaque(observer).takeUnretainedValue().pullInbox()
      },
      Self.inboxNotification as CFString, nil, .deliverImmediately)
    pullInbox()
  }

  // MARK: - share extension inbox

  /// Imports finished batches from <group>/Inbox and tells Dart (it then calls takeShared).
  @objc func pullInbox() {
    io.async {
      guard
        let root = self.fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)
      else { return }
      let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
      let batches = ((try? self.fm.contentsOfDirectory(atPath: inbox.path)) ?? [])
        .filter { !$0.hasPrefix(".") && !$0.hasSuffix(".part") }
        .sorted()
      var items: [(URL, String)] = []
      var done: [URL] = []
      for b in batches {
        let dir = inbox.appendingPathComponent(b, isDirectory: true)
        done.append(dir)
        for slot in ((try? self.fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() {
          let sd = dir.appendingPathComponent(slot, isDirectory: true)
          for f in ((try? self.fm.contentsOfDirectory(atPath: sd.path)) ?? []).sorted() {
            items.append((sd.appendingPathComponent(f), f))
          }
        }
      }
      // Stale half-written batches (extension killed mid-copy)
      for b in ((try? self.fm.contentsOfDirectory(atPath: inbox.path)) ?? []) where b.hasSuffix(".part") {
        let u = inbox.appendingPathComponent(b)
        if let d = (try? self.fm.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date,
          Date().timeIntervalSince(d) > 600
        {
          try? self.fm.removeItem(at: u)
        }
      }
      guard !done.isEmpty else { return }
      let files = items.isEmpty ? [] : self.importFiles(items)
      for d in done { try? self.fm.removeItem(at: d) }
      guard !files.isEmpty else { return }
      DispatchQueue.main.async {
        self.pendingShared = (self.pendingShared ?? []) + files
        self.channel.invokeMethod("shared", arguments: nil)
      }
    }
  }

  // MARK: - plumbing

  private struct Failure: LocalizedError {
    let msg: String
    var errorDescription: String? { msg }
  }

  private func background(_ result: @escaping FlutterResult, _ work: @escaping () throws -> Any?) {
    io.async {
      do {
        let v = try work()
        DispatchQueue.main.async { result(v) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "io", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let tree = args["tree"] as? String ?? ""
    switch call.method {
    case "cacheDir":
      result(root.path)
    case "pickImages":
      if args["gallery"] as? Bool == true { pickPhotos(result) } else { pickFiles(result) }
    case "pickFolder":
      let p = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
      present(p, kind: .folder, result)
    case "importTree":
      let recursive = args["recursive"] as? Bool ?? false
      background(result) { try self.importTree(tree, recursive: recursive) }
    case "treeName":
      background(result) {
        try self.withTree(tree) { url in
          guard self.fm.fileExists(atPath: url.path) else { throw Failure(msg: "folder is gone") }
          return url.lastPathComponent
        }
      }
    case "moveToOld":
      let dir = args["dir"] as? String ?? ""
      let regex = args["regex"] as? String ?? "$^"
      background(result) { try self.moveToOld(tree, dir, regex) }
    case "writeFile":
      let rel = args["relPath"] as? String ?? ""
      let src = URL(fileURLWithPath: args["src"] as? String ?? "")
      let backup = args["backup"] as? Bool ?? false
      background(result) { try self.writeFile(tree, rel, src, backup: backup) }
    case "openTree":
      openTree(tree, args["dir"] as? String ?? "", result)
    case "galleryAvailable":
      result(true)
    case "saveToGallery":
      let src = URL(fileURLWithPath: args["src"] as? String ?? "")
      saveToGallery(src, album: args["album"] as? String ?? "Image Compressor", result)
    case "openGallery":
      if let url = URL(string: "photos-redirect://") {
        UIApplication.shared.open(url) { ok in result(ok) }
      } else {
        result(false)
      }
    case "takeShared":
      result(pendingShared)
      pendingShared = nil
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - pickers

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    var vc = window?.rootViewController
    while let p = vc?.presentedViewController { vc = p }
    return vc
  }

  private func present(_ vc: UIViewController, kind: Kind, _ result: @escaping FlutterResult) {
    pending?(FlutterError(code: "cancelled", message: "superseded", details: nil))
    pending = result
    pendingKind = kind
    if let p = vc as? UIDocumentPickerViewController { p.delegate = self }
    guard let top = topViewController() else {
      pending = nil
      result(FlutterError(code: "no_picker", message: "no view controller", details: nil))
      return
    }
    top.present(vc, animated: true)
  }

  private func takePending() -> FlutterResult? {
    let r = pending
    pending = nil
    return r
  }

  private func pickFiles(_ result: @escaping FlutterResult) {
    // asCopy: the picker copies the files into our sandbox, no security scope needed
    let p = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
    p.allowsMultipleSelection = true
    present(p, kind: .images, result)
  }

  private func pickPhotos(_ result: @escaping FlutterResult) {
    var cfg = PHPickerConfiguration()
    cfg.filter = .images
    cfg.selectionLimit = 0
    // Keep the original encoding (HEIC stays HEIC instead of being transcoded to JPEG)
    cfg.preferredAssetRepresentationMode = .current
    let p = PHPickerViewController(configuration: cfg)
    p.delegate = self
    present(p, kind: .images, result)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = takePending() else { return }
    switch pendingKind {
    case .folder:
      guard let url = urls.first else { return result(nil) }
      let ok = url.startAccessingSecurityScopedResource()
      defer { if ok { url.stopAccessingSecurityScopedResource() } }
      do {
        let bm = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        result(["uri": Self.treePrefix + bm.base64EncodedString(), "name": url.lastPathComponent])
      } catch {
        result(FlutterError(code: "io", message: error.localizedDescription, details: nil))
      }
    case .images:
      background(result) {
        let r = self.importFiles(urls.map { ($0, $0.lastPathComponent) })
        for u in urls { try? self.fm.removeItem(at: u) }  // the picker's copies
        return r
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    takePending()?(nil)
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let result = takePending() else { return }
    if results.isEmpty { return result(nil) }
    let staging = newImportDir().appendingPathComponent("photos", isDirectory: true)
    try? fm.createDirectory(at: staging, withIntermediateDirectories: true)
    var got = [(URL, String)?](repeating: nil, count: results.count)
    let lock = NSLock()
    let group = DispatchGroup()
    for (i, r) in results.enumerated() {
      let provider = r.itemProvider
      guard
        let type = provider.registeredTypeIdentifiers.first(where: {
          UTType($0)?.conforms(to: .image) == true
        })
      else { continue }
      group.enter()
      provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
        defer { group.leave() }
        guard let url else { return }
        var name = provider.suggestedName ?? url.deletingPathExtension().lastPathComponent
        let ext = UTType(type)?.preferredFilenameExtension ?? url.pathExtension
        if (name as NSString).pathExtension.isEmpty || !Self.isImageName(name) {
          name += "." + ext
        }
        // The file is deleted when this callback returns: copy it now
        let tmp = staging.appendingPathComponent("\(i)_" + UUID().uuidString + "." + ext)
        if (try? self.fm.copyItem(at: url, to: tmp)) != nil {
          lock.lock()
          got[i] = (tmp, name)
          lock.unlock()
        }
      }
    }
    group.notify(queue: io) {
      let picked = got.compactMap { $0 }
      let r = self.importFiles(picked)
      try? self.fm.removeItem(at: staging)
      DispatchQueue.main.async { result(r) }
    }
  }

  // MARK: - import

  private func newImportDir() -> URL {
    importSeq += 1
    let d = root.appendingPathComponent(
      "import/\(Int(Date().timeIntervalSince1970 * 1000))_\(importSeq)", isDirectory: true)
    try? fm.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }

  private func safeName(_ name: String) -> String {
    let bad = CharacterSet(charactersIn: "\\/:*?\"<>|\0")
    let s = name.components(separatedBy: bad).joined(separator: "_")
    return s.trimmingCharacters(in: .whitespaces).isEmpty ? "image" : s
  }

  /// Single files (picker / share): copied to a fresh folder, keeping their names.
  func importFiles(_ items: [(URL, String)]) -> [[String: Any]] {
    let dir = newImportDir()
    var used = Set<String>()
    var out: [[String: Any]] = []
    for (src, raw) in items {
      let name = safeName(raw)
      guard Self.isImageName(name) else { continue }
      // Same name twice (e.g. two IMG_0001.HEIC): add a counter
      let stem = (name as NSString).deletingPathExtension
      let ext = (name as NSString).pathExtension
      var unique = name
      var n = 1
      while !used.insert(unique.lowercased()).inserted {
        unique = "\(stem) (\(n)).\(ext)"
        n += 1
      }
      let dst = dir.appendingPathComponent(unique)
      do {
        try copyIn(src, dst)
        out.append(["path": dst.path, "name": unique])
      } catch {}
    }
    return out
  }

  /// Coordinated copy so iCloud Drive / File Provider items are downloaded first.
  private func copyIn(_ src: URL, _ dst: URL) throws {
    try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
    var cerr: NSError?
    var ierr: Error?
    NSFileCoordinator().coordinate(readingItemAt: src, options: [], error: &cerr) { u in
      do {
        try? self.fm.removeItem(at: dst)
        try self.fm.copyItem(at: u, to: dst)
      } catch { ierr = error }
    }
    if let e = cerr ?? ierr { throw e }
  }

  // MARK: - folders

  private func resolve(_ tree: String) throws -> URL {
    guard tree.hasPrefix(Self.treePrefix),
      let data = Data(base64Encoded: String(tree.dropFirst(Self.treePrefix.count)))
    else { throw Failure(msg: "invalid folder reference") }
    var stale = false
    return try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
  }

  private func withTree<T>(_ tree: String, _ body: (URL) throws -> T) throws -> T {
    let url = try resolve(tree)
    let ok = url.startAccessingSecurityScopedResource()
    defer { if ok { url.stopAccessingSecurityScopedResource() } }
    return try body(url)
  }

  private func sub(_ base: URL, _ rel: String) -> URL {
    rel.split(separator: "/").reduce(base) { $0.appendingPathComponent(String($1)) }
  }

  private func isDir(_ u: URL) -> Bool {
    var d: ObjCBool = false
    return fm.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
  }

  /// (url to read, real name); iCloud placeholders ".name.icloud" map to the real item.
  private func listing(_ dir: URL) -> [(URL, String, Bool)] {
    let kids = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
    var out: [(URL, String, Bool)] = []
    for k in kids {
      let n = k.lastPathComponent
      if n.hasPrefix("."), n.hasSuffix(".icloud") {
        let real = String(n.dropFirst().dropLast(".icloud".count))
        out.append((dir.appendingPathComponent(real), real, false))
      } else if !n.hasPrefix(".") {
        out.append((k, n, isDir(k)))
      }
    }
    return out.sorted { $0.1.lowercased() < $1.1.lowercased() }
  }

  /// Copies the images of a picked folder into the cache, mirroring sub folders.
  private func importTree(_ tree: String, recursive: Bool) throws -> [String: Any] {
    try withTree(tree) { top in
      let base = newImportDir()
      var files: [[String: Any]] = []
      func walk(_ dir: URL, _ rel: String) {
        for (u, name, folder) in listing(dir) {
          let path = rel.isEmpty ? name : "\(rel)/\(name)"
          if folder {
            if recursive && name != "_old" { walk(u, path) }
          } else if Self.isImageName(name) {
            let dst = base.appendingPathComponent(path)
            if (try? copyIn(u, dst)) != nil {
              files.append(["path": dst.path, "name": name, "relDir": rel])
            }
          }
        }
      }
      walk(top, "")
      return ["base": base.path, "name": top.lastPathComponent, "files": files]
    }
  }

  /// Moves one file into <its folder>/_old (adds " (n)" when the name is taken).
  private func moveOne(_ file: URL) throws {
    let old = file.deletingLastPathComponent().appendingPathComponent("_old", isDirectory: true)
    try fm.createDirectory(at: old, withIntermediateDirectories: true)
    let taken = Set(((try? fm.contentsOfDirectory(atPath: old.path)) ?? []).map { $0.lowercased() })
    let name = file.lastPathComponent
    let stem = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var target = name
    var n = 1
    while taken.contains(target.lowercased()) {
      target = "\(stem) (\(n)).\(ext)"
      n += 1
    }
    let dst = old.appendingPathComponent(target)
    var cerr: NSError?
    var ierr: Error?
    NSFileCoordinator().coordinate(
      writingItemAt: file, options: .forMoving, writingItemAt: dst, options: .forReplacing, error: &cerr
    ) { s, d in
      do { try self.fm.moveItem(at: s, to: d) } catch { ierr = error }
    }
    if let e = cerr ?? ierr { throw e }
  }

  /// Moves files in relDir whose names match regex into relDir/_old. Returns the count.
  private func moveToOld(_ tree: String, _ relDir: String, _ regex: String) throws -> Int {
    let re = try NSRegularExpression(pattern: "^(?:\(regex))$")
    return try withTree(tree) { top in
      let dir = sub(top, relDir)
      guard isDir(dir) else { return 0 }
      let victims = listing(dir).filter { u, name, d in
        !d && fm.fileExists(atPath: u.path)
          && re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
      }
      for (u, _, _) in victims { try moveOne(u) }
      return victims.count
    }
  }

  /// Writes src to relPath under the tree. backup = move an existing file to _old first.
  private func writeFile(_ tree: String, _ relPath: String, _ src: URL, backup: Bool) throws -> String {
    try withTree(tree) { top in
      let target = sub(top, relPath)
      try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      if backup && fm.fileExists(atPath: target.path) { try moveOne(target) }
      var cerr: NSError?
      var ierr: Error?
      NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &cerr) { u in
        do {
          if self.fm.fileExists(atPath: u.path) { try self.fm.removeItem(at: u) }
          try self.fm.copyItem(at: src, to: u)
        } catch { ierr = error }
      }
      if let e = cerr ?? ierr { throw e }
      return target.path
    }
  }

  // MARK: - Photos

  private var albums: [String: PHAssetCollection] = [:]

  /// Saves src into the Photos album (created on first use). Needs read-write access
  /// because add-only access cannot see or create albums; falls back to the library alone.
  private func saveToGallery(_ src: URL, album: String, _ result: @escaping FlutterResult) {
    PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async {
          result(FlutterError(code: "denied", message: "Photos access denied", details: nil))
        }
        return
      }
      self.background(result) {
        let collection = self.album(named: album)
        do {
          try self.addAsset(src, to: collection)
        } catch where collection != nil {
          try self.addAsset(src, to: nil)
        }
        return nil
      }
    }
  }

  /// Runs on the io queue.
  private func album(named title: String) -> PHAssetCollection? {
    if let c = albums[title] { return c }
    let opts = PHFetchOptions()
    opts.predicate = NSPredicate(format: "title = %@", title)
    var found = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: opts)
      .firstObject
    if found == nil {
      var id: String?
      try? PHPhotoLibrary.shared().performChangesAndWait {
        id = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
          .placeholderForCreatedAssetCollection.localIdentifier
      }
      if let id {
        found = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
      }
    }
    albums[title] = found
    return found
  }

  private func addAsset(_ src: URL, to collection: PHAssetCollection?) throws {
    try PHPhotoLibrary.shared().performChangesAndWait {
      let opts = PHAssetResourceCreationOptions()
      opts.originalFilename = src.lastPathComponent
      let req = PHAssetCreationRequest.forAsset()
      req.addResource(with: .photo, fileURL: src, options: opts)
      if let collection, let ph = req.placeholderForCreatedAsset,
        let change = PHAssetCollectionChangeRequest(for: collection)
      {
        change.addAssets([ph] as NSArray)
      }
    }
  }

  /// Opens the folder in the Files app.
  private func openTree(_ tree: String, _ relDir: String, _ result: @escaping FlutterResult) {
    guard let top = try? resolve(tree) else { return result(false) }
    let path = sub(top, relDir).path
    guard let enc = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
      let url = URL(string: "shareddocuments://" + enc)
    else { return result(false) }
    UIApplication.shared.open(url) { ok in result(ok) }
  }
}
