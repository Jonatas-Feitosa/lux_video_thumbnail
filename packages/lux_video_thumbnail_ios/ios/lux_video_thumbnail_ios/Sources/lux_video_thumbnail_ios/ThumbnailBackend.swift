import AVFoundation
import Flutter
import UIKit

private final class VideoSession {
    let asset: AVURLAsset
    let generator: AVAssetImageGenerator
    let input: URL?
    let durationMs: Int64?
    let width: Int
    let height: Int

    init(asset: AVURLAsset, input: URL?, durationMs: Int64?, width: Int, height: Int) {
        self.asset = asset
        self.generator = AVAssetImageGenerator(asset: asset)
        self.generator.appliesPreferredTrackTransform = true
        self.input = input
        self.durationMs = durationMs
        self.width = width
        self.height = height
    }

    func release() {
        generator.cancelAllCGImageGeneration()
        asset.cancelLoading()
    }
}

final class ThumbnailBackend {
    private var sessions: [Int64: VideoSession] = [:]
    private var nextHandle: Int64 = 1
    private let files = OwnedTemporaryFiles()

    func handle(_ method: String, _ args: [String: Any]) throws -> Any? {
        switch method {
        case "getPlatformVersion":
            return "iOS " + ProcessInfo.processInfo.operatingSystemVersionString
        case "openSession", "openSessionFromBytes":
            guard sessions.count < 4 else {
                throw ThumbnailFailure(code: "RESOURCE_LIMIT", message: "At most four sessions may be open")
            }
            var input: URL?
            do {
                let url: URL
                if method == "openSessionFromBytes" || args["bytes"] != nil {
                    guard let bytes = args["bytes"] as? FlutterStandardTypedData,
                          !bytes.data.isEmpty else {
                        throw ThumbnailFailure(code: "ARGUMENT_ERROR", message: "Missing video bytes")
                    }
                    guard bytes.data.count <= ThumbnailPolicy.maxVideoBytes else {
                        throw ThumbnailFailure(code: "RESOURCE_LIMIT", message: "Video exceeds 64 MiB")
                    }
                    let mime = try ThumbnailPolicy.text(args["mimeType"] ?? "video/mp4", "mimeType", max: 128)
                    guard mime.range(of: "^video/[a-zA-Z0-9.+-]+$", options: .regularExpression) != nil else {
                        throw ThumbnailFailure(code: "ARGUMENT_ERROR", message: "Expected video MIME type")
                    }
                    let suffix: String
                    switch mime.lowercased() {
                    case "video/quicktime": suffix = "mov"
                    case "video/x-m4v": suffix = "m4v"
                    case "video/webm": suffix = "webm"
                    default: suffix = "mp4"
                    }
                    let owned = try files.create(input: true, extension: suffix)
                    input = owned
                    try bytes.data.write(to: owned, options: .atomic)
                    url = owned
                } else {
                    url = try sourceURL(args["source"])
                }
                let session = try open(url, input: input)
                let handle = nextHandle
                nextHandle += 1
                sessions[handle] = session
                return ["nativeHandle": handle, "duration": session.durationMs.map { $0 as Any } ?? NSNull(),
                        "nativeWidth": session.width, "nativeHeight": session.height]
            } catch {
                files.deleteInput(input)
                throw error
            }
        case "closeSession":
            let handle = try ThumbnailPolicy.integer(args["sessionHandle"], "sessionHandle", min: 1)
            if let session = sessions.removeValue(forKey: handle) {
                session.release()
                files.deleteInput(session.input)
            }
            return nil
        case "generateThumbnails":
            let handle = try ThumbnailPolicy.integer(args["sessionHandle"], "sessionHandle", min: 1)
            guard let session = sessions[handle] else {
                throw ThumbnailFailure(code: "SESSION_INVALID", message: "Session is closed or unknown")
            }
            guard let options = args["options"] as? [[String: Any]], !options.isEmpty else {
                throw ThumbnailFailure(code: "ARGUMENT_ERROR", message: "Expected nonempty options list")
            }
            guard options.count <= 16 else {
                throw ThumbnailFailure(code: "RESOURCE_LIMIT", message: "Batch exceeds 16 thumbnails")
            }
            try reserve(options.count)
            // Validate the whole batch before creating any output.
            for option in options {
                try ThumbnailPolicy.validate(option)
                _ = try ThumbnailPolicy.timestamp(option, durationMs: session.durationMs)
                _ = try ThumbnailPolicy.outputSize(option, width: session.width, height: session.height)
            }
            var results: [[String: Any]] = []
            do {
                for option in options {
                    let output = try autoreleasepool { try generate(session, option) }
                    results.append(output)
                }
                return results
            } catch {
                for output in results { if let path = output["tempPath"] as? String { try? files.deleteThumbnail(path) } }
                throw error
            }
        case "generateThumbnail":
            try reserveDecoder()
            guard let options = args["options"] as? [String: Any] else {
                throw ThumbnailFailure(code: "ARGUMENT_ERROR", message: "Missing options")
            }
            try ThumbnailPolicy.validate(options)
            try reserve(1)
            let session = try open(sourceURL(args["source"]), input: nil)
            defer { session.release() }
            return try generate(session, options)
        case "getVideoDuration":
            try reserveDecoder()
            let session = try open(sourceURL(args["source"]), input: nil)
            defer { session.release() }
            return session.durationMs
        case "isFormatSupported":
            let mime = try ThumbnailPolicy.text(args["mimeType"], "mimeType", max: 128)
            return AVURLAsset.audiovisualMIMETypes().contains(mime.lowercased())
        case "readThumbnailChunk", "getThumbnailFileSize", "deleteThumbnailFile":
            let path = try ThumbnailPolicy.text(args["path"], "path")
            let url = try files.thumbnail(path)
            if method == "deleteThumbnailFile" { try files.deleteThumbnail(path); return nil }
            let reader = try FileHandle(forReadingFrom: url)
            defer { reader.closeFile() }
            let size = reader.seekToEndOfFile()
            if method == "getThumbnailFileSize" { return Int64(size) }
            let offset = try ThumbnailPolicy.integer(args["offset"] ?? 0, "offset")
            guard UInt64(offset) <= size else {
                throw ThumbnailFailure(code: "ARGUMENT_ERROR", message: "Offset exceeds thumbnail length")
            }
            let count = try ThumbnailPolicy.integer(args["length"] ?? ThumbnailPolicy.maxImageBytes,
                                                    "length", max: Int64(ThumbnailPolicy.maxImageBytes))
            reader.seek(toFileOffset: UInt64(offset))
            return FlutterStandardTypedData(bytes: reader.readData(ofLength: Int(Swift.min(UInt64(count), size - UInt64(offset)))))
        case "copyThumbnailFile":
            let source = try files.thumbnail(ThumbnailPolicy.text(args["sourcePath"], "sourcePath"))
            let target = URL(fileURLWithPath: try ThumbnailPolicy.text(args["targetPath"], "targetPath"))
                .standardizedFileURL
            // Copying to another owned resource would invalidate its lifecycle.
            guard !target.path.hasPrefix(source.deletingLastPathComponent().path + "/"),
                  !target.resolvingSymlinksInPath().path.hasPrefix(source.deletingLastPathComponent().path + "/") else {
                throw ThumbnailFailure(code: "PERMISSION_DENIED", message: "Cannot overwrite plugin temporaries")
            }
            // FileManager.copyItem refuses to overwrite an existing caller file.
            try FileManager.default.copyItem(at: source, to: target)
            return nil
        default:
            return FlutterMethodNotImplemented
        }
    }

    private func reserve(_ count: Int) throws {
        guard files.thumbnailCount + count <= 64 else {
            throw ThumbnailFailure(code: "RESOURCE_LIMIT", message: "At most 64 thumbnail temporaries may be retained")
        }
    }

    private func reserveDecoder() throws {
        guard sessions.count < 4 else {
            throw ThumbnailFailure(code: "RESOURCE_LIMIT", message: "Close a session before opening another decoder")
        }
    }

    private func sourceURL(_ raw: Any?) throws -> URL {
        let source = try ThumbnailPolicy.text(raw, "source")
        let url: URL
        if source.hasPrefix("/") { url = URL(fileURLWithPath: source) }
        else if let parsed = URL(string: source), ["file", "http", "https"].contains(parsed.scheme?.lowercased() ?? "") {
            url = parsed
        } else {
            throw ThumbnailFailure(code: "ARGUMENT_ERROR", message: "Use an absolute file path, file URL or HTTP(S) URL")
        }
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ThumbnailFailure(code: "VIDEO_NOT_FOUND", message: "Video file does not exist")
            }
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw ThumbnailFailure(code: "PERMISSION_DENIED", message: "Video file is not readable")
            }
        }
        return url
    }

    // Compatible with iOS 13. Loading and synchronous image generation never
    // block Flutter's main thread. Metadata loads time out after 30 seconds.
    private func load(_ object: AVAsynchronousKeyValueLoading, keys: [String]) throws {
        let ready = DispatchSemaphore(value: 0)
        object.loadValuesAsynchronously(forKeys: keys) { ready.signal() }
        guard ready.wait(timeout: .now() + 30) == .success else {
            throw ThumbnailFailure(code: "GENERATION_FAILED", message: "Video metadata load timed out")
        }
        for key in keys {
            var error: NSError?
            guard object.statusOfValue(forKey: key, error: &error) == .loaded else {
                throw ThumbnailFailure(code: "UNSUPPORTED_FORMAT", message: error?.localizedDescription ?? "Cannot load video metadata")
            }
        }
    }

    private func open(_ url: URL, input: URL?) throws -> VideoSession {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        do {
            try load(asset, keys: ["tracks", "duration", "playable", "hasProtectedContent"])
            guard asset.isPlayable, !asset.hasProtectedContent,
                  let track = asset.tracks(withMediaType: .video).first else {
                throw ThumbnailFailure(code: "UNSUPPORTED_FORMAT", message: "No playable, unprotected video track")
            }
            try load(track, keys: ["naturalSize", "preferredTransform"])
            let size = track.naturalSize.applying(track.preferredTransform)
            let w = abs(size.width), h = abs(size.height)
            guard w.isFinite, h.isFinite, w >= 1, h >= 1, w <= 4096, h <= 4096 else {
                throw ThumbnailFailure(code: "RESOURCE_LIMIT", message: "Source dimensions exceed resource limits")
            }
            let width = Int(w.rounded()), height = Int(h.rounded())
            try ThumbnailPolicy.dimensions(width, height)
            let seconds = CMTimeGetSeconds(asset.duration)
            let milliseconds = seconds * 1000
            let duration: Int64? = milliseconds.isFinite && milliseconds >= 1 && milliseconds <= Double(ThumbnailPolicy.maxTimestamp / 1000)
                ? Int64(milliseconds.rounded(.down)) : nil
            return VideoSession(asset: asset, input: input, durationMs: duration, width: width, height: height)
        } catch {
            asset.cancelLoading()
            throw error
        }
    }

    private func generate(_ session: VideoSession, _ options: [String: Any]) throws -> [String: Any] {
        try ThumbnailPolicy.validate(options)
        let timestamp = try ThumbnailPolicy.timestamp(options, durationMs: session.durationMs)
        let (width, height) = try ThumbnailPolicy.outputSize(options, width: session.width, height: session.height)
        let generator = session.generator
        let keyframe = options["preferKeyFrame"] as? Bool == true
        generator.requestedTimeToleranceBefore = keyframe ? .positiveInfinity : .zero
        generator.requestedTimeToleranceAfter = keyframe ? .positiveInfinity : .zero
        // Bound decoder output before creating the bitmap; preferred transform
        // honors portrait/rotated sources. Draw to final dimensions afterwards.
        generator.maximumSize = CGSize(width: CGFloat(session.width), height: CGFloat(session.height))
        let frame = try generator.copyCGImage(at: CMTime(value: timestamp, timescale: 1_000_000), actualTime: nil)
        try ThumbnailPolicy.dimensions(frame.width, frame.height)
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true
        rendererFormat.preferredRange = .standard
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let image = UIGraphicsImageRenderer(size: bounds.size, format: rendererFormat).image { context in
            UIColor.black.setFill()
            context.fill(bounds)
            UIImage(cgImage: frame).draw(in: bounds)
        }
        let format = options["format"] as? String ?? "jpeg"
        let quality = CGFloat((options["quality"] as? NSNumber)?.doubleValue ?? 85) / 100
        guard let data = format == "png" ? image.pngData() : image.jpegData(compressionQuality: quality) else {
            throw ThumbnailFailure(code: "GENERATION_FAILED", message: "Cannot encode thumbnail")
        }
        guard data.count <= ThumbnailPolicy.maxImageBytes else {
            throw ThumbnailFailure(code: "RESOURCE_LIMIT", message: "Encoded image exceeds 8 MiB; reduce dimensions or quality")
        }
        let output = try files.create(input: false, extension: format == "png" ? "png" : "jpg")
        do { try data.write(to: output, options: .atomic) }
        catch { try? files.deleteThumbnail(output.path); throw error }
        return ["width": width, "height": height, "format": format,
                "actualTimestamp": timestamp / 1000, "effectiveTimestampUs": timestamp,
                "backingType": "file", "tempPath": output.path]
    }

    func cleanup() {
        for session in sessions.values { session.release() }
        sessions.removeAll()
        files.cleanup()
    }
}
