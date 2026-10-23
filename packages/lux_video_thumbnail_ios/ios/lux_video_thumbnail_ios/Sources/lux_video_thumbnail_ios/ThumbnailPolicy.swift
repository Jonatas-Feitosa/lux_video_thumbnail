import Foundation
import CoreFoundation

struct ThumbnailFailure: Error {
    let code: String
    let message: String
    var details: [String: Any]? = nil
}

enum ThumbnailPolicy {
    static let maxVideoBytes = 64 * 1024 * 1024
    static let maxImageBytes = 8 * 1024 * 1024
    static let maxTimestamp: Int64 = 9_007_199_254_740_991

    static func integer(_ value: Any?, _ name: String, min: Int64 = 0,
                        max: Int64 = ThumbnailPolicy.maxTimestamp) throws -> Int64 {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw ThumbnailFailure(code: "ARGUMENT_ERROR", message: "\(name) must be an integer")
        }
        let double = number.doubleValue
        guard double.isFinite, double.rounded(.towardZero) == double,
              double >= Double(min), double <= Double(max) else {
            throw ThumbnailFailure(code: "ARGUMENT_ERROR", message: "Invalid \(name)")
        }
        return number.int64Value
    }

    static func text(_ value: Any?, _ name: String, max: Int = 16384) throws -> String {
        guard let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              string.utf16.count <= max, !string.contains("\0") else {
            throw ThumbnailFailure(code: "ARGUMENT_ERROR", message: "Invalid \(name)")
        }
        return string
    }

    static func dimensions(_ width: Int, _ height: Int) throws {
        guard (1...4096).contains(width), (1...4096).contains(height), width * height <= 16777216 else {
            throw ThumbnailFailure(code: "RESOURCE_LIMIT", message: "Image dimensions exceed 4096 or 16 megapixels")
        }
    }

    static func validate(_ options: [String: Any]) throws {
        for key in ["timestampUs", "timestampMs"] where options[key] != nil {
            _ = try integer(options[key], key, min: -maxTimestamp,
                            max: key == "timestampMs" ? maxTimestamp / 1000 : maxTimestamp)
        }
        for key in ["width", "height"] where options[key] != nil {
            _ = try integer(options[key], key, min: 1, max: 4096)
        }
        if let quality = options["quality"] {
            _ = try integer(quality, "quality", min: 1, max: 100)
        }
        if let format = options["format"] {
            guard let name = format as? String, ["jpeg", "png", "webp"].contains(name) else {
                throw ThumbnailFailure(code: "ARGUMENT_ERROR", message: "Invalid output format")
            }
            if name == "webp" {
                throw ThumbnailFailure(code: "UNSUPPORTED_FORMAT", message: "iOS output supports JPEG and PNG; WebP encoding is unavailable")
            }
        }
        for key in ["maintainAspectRatio", "preferKeyFrame"] where options[key] != nil {
            guard let number = options[key] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw ThumbnailFailure(code: "ARGUMENT_ERROR", message: "\(key) must be boolean")
            }
        }
    }

    static func timestamp(_ options: [String: Any], durationMs: Int64?) throws -> Int64 {
        let requested: Int64
        if let microseconds = options["timestampUs"] {
            requested = try integer(microseconds, "timestampUs", min: -maxTimestamp)
        } else {
            requested = try integer(options["timestampMs"] ?? 0, "timestampMs", min: -maxTimestamp / 1000,
                                    max: maxTimestamp / 1000) * 1000
        }
        let end = durationMs.map { $0 * 1000 }
        if requested < 0 || (end != nil && requested > end!) {
            throw ThumbnailFailure(code: "TIMESTAMP_OUT_OF_RANGE", message: "Timestamp is outside the video timeline",
                                   details: ["requestedUs": requested, "requestedMs": requested / 1000,
                                             "durationMs": durationMs.map { $0 as Any } ?? NSNull()])
        }
        return end == requested ? Swift.max(0, requested - 1) : requested
    }

    static func outputSize(_ options: [String: Any], width: Int, height: Int) throws -> (Int, Int) {
        try dimensions(width, height)
        var w = (options["width"] as? NSNumber)?.intValue ?? width
        var h = (options["height"] as? NSNumber)?.intValue ?? height
        let aspect = Double(width) / Double(height)
        if options["width"] == nil && options["height"] != nil {
            w = Swift.max(1, Int((Double(h) * aspect).rounded()))
        } else if options["height"] == nil && options["width"] != nil {
            h = Swift.max(1, Int((Double(w) / aspect).rounded()))
        } else if options["maintainAspectRatio"] as? Bool != false && options["width"] != nil && options["height"] != nil {
            if Double(w) / Double(h) > aspect { w = Swift.max(1, Int((Double(h) * aspect).rounded())) }
            else { h = Swift.max(1, Int((Double(w) / aspect).rounded())) }
        }
        try dimensions(w, h)
        return (w, h)
    }
}
