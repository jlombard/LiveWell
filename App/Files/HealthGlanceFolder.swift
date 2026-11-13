import Foundation
import LiveWellCore

/// Access to iCloud Drive's Health Glance folder, picked once and remembered with a bookmark.
/// Every read and write goes through NSFileCoordinator so iCloud never sees a half-written file.
final class HealthGlanceFolder: NSObject, NSFilePresenter {
    private static let bookmarkKey = "healthGlanceBookmark"

    private(set) var url: URL?
    private var accessing = false
    /// Called on the main queue when data.json changes.
    var onDashboardChange: (() -> Void)?

    override init() {
        super.init()
        resolve()
    }

    var isLinked: Bool { url != nil }
    var displayName: String { url?.lastPathComponent ?? "Not linked" }

    func link(_ picked: URL) throws {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let bookmark = try picked.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        resolve()
    }

    private func resolve() {
        stopPresenting()
        if accessing, let url { url.stopAccessingSecurityScopedResource() }
        accessing = false
        url = nil
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil,
                                      bookmarkDataIsStale: &stale) else { return }
        accessing = resolved.startAccessingSecurityScopedResource()
        if stale, let fresh = try? resolved.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        url = resolved
        NSFileCoordinator.addFilePresenter(self)
    }

    private func stopPresenting() {
        if url != nil { NSFileCoordinator.removeFilePresenter(self) }
    }

    enum FolderError: LocalizedError {
        case notLinked
        var errorDescription: String? { "The Health Glance folder isn't linked yet." }
    }

    // MARK: coordinated read and write

    func read(_ relativePath: String) throws -> Data {
        guard let url else { throw FolderError.notLinked }
        let target = url.appendingPathComponent(relativePath)
        try? FileManager.default.startDownloadingUbiquitousItem(at: target)
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(FolderError.notLinked)
        NSFileCoordinator(filePresenter: self).coordinate(readingItemAt: target, options: [], error: &coordinationError) { u in
            result = Result { try Data(contentsOf: u) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    func exists(_ relativePath: String) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent(relativePath).path)
    }

    /// Whole-file atomic write. Skips identical content unless `always` is set.
    @discardableResult
    func write(_ text: String, to relativePath: String, always: Bool = false) throws -> AtomicFile.Outcome {
        guard let url else { throw FolderError.notLinked }
        let target = url.appendingPathComponent(relativePath)
        var coordinationError: NSError?
        var result: Result<AtomicFile.Outcome, Error> = .failure(FolderError.notLinked)
        NSFileCoordinator(filePresenter: self).coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { u in
            result = Result { try AtomicFile.write(text, to: u, always: always) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    // MARK: NSFilePresenter (watches the folder for a new data.json from the Mac)

    var presentedItemURL: URL? { url }
    let presentedItemOperationQueue: OperationQueue = .main

    func presentedSubitemDidChange(at changed: URL) {
        if changed.lastPathComponent == "data.json" { onDashboardChange?() }
    }

    func presentedItemDidChange() {
        onDashboardChange?()
    }
}
