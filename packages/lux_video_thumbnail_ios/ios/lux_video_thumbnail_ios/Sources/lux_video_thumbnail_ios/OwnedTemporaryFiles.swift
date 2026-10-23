import Foundation

// Accessed only by the engine's serial worker. A source path never grants
// ownership. Input files and returned thumbnail files have separate lifetimes.
final class OwnedTemporaryFiles {
    private var directory: URL?
    private var thumbnails = Set<String>()
    private var inputs = Set<String>()
    var thumbnailCount: Int { thumbnails.count }

    func create(input: Bool, extension suffix: String) throws -> URL {
        if directory == nil {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lux-thumbnail-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            directory = url.resolvingSymlinksInPath().standardizedFileURL
        }
        let url = directory!.appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ThumbnailFailure(code: "GENERATION_FAILED", message: "Cannot create temporary file")
        }
        if input { inputs.insert(url.path) } else { thumbnails.insert(url.path) }
        return url
    }

    func thumbnail(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard thumbnails.contains(path), url.path == path,
              url.resolvingSymlinksInPath().path == path else {
            throw ThumbnailFailure(code: "PERMISSION_DENIED", message: "Only owned thumbnails may be accessed")
        }
        return url
    }

    func deleteThumbnail(_ path: String) throws {
        // Dart makes disposal idempotent; arbitrary paths are never deleted.
        _ = try thumbnail(path)
        if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
        thumbnails.remove(path)
    }

    func deleteInput(_ url: URL?) {
        guard let url = url, inputs.remove(url.path) != nil else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func cleanup() {
        // Only this engine's private directory is removed.
        if let directory = directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        thumbnails.removeAll()
        inputs.removeAll()
    }
}
