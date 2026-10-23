import Flutter
import UIKit

public final class LuxVideoThumbnailPlugin: NSObject, FlutterPlugin {
    private let worker = DispatchQueue(label: "lux_video_thumbnail.ios", qos: .userInitiated)
    private let backend = ThumbnailBackend()
    private let lock = NSLock()
    private var detached = false
    // Flutter calls and replies run on the main thread; media/IO run on worker.
    private var replies: [UUID: FlutterResult] = [:]
    private var queuedBytes = 0
    private var channel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "lux_video_thumbnail", binaryMessenger: registrar.messenger())
        let instance = LuxVideoThumbnailPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.publish(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard !isDetached else {
            result(FlutterError(code: "ENGINE_DETACHED", message: "Flutter engine is detached", details: nil))
            return
        }
        let arguments = clean(call.arguments) as? [String: Any] ?? [:]
        let weight = (arguments["bytes"] as? FlutterStandardTypedData)?.data.count ?? 0
        guard replies.count < 16, weight <= ThumbnailPolicy.maxVideoBytes - queuedBytes else {
            result(FlutterError(code: "RESOURCE_LIMIT", message: "Engine queue exceeds 16 operations or 64 MiB", details: nil))
            return
        }
        let id = UUID()
        replies[id] = result
        queuedBytes += weight
        worker.async { [self] in
            guard !isDetached else { return }
            let response: Any? = autoreleasepool {
                do { return try backend.handle(call.method, arguments) }
                catch let failure as ThumbnailFailure {
                    return FlutterError(code: failure.code, message: failure.message, details: failure.details)
                } catch {
                    return FlutterError(code: "GENERATION_FAILED", message: error.localizedDescription, details: nil)
                }
            }
            DispatchQueue.main.async { [self] in
                guard let reply = replies.removeValue(forKey: id) else { return }
                queuedBytes -= weight
                reply(response)
            }
        }
    }

    private var isDetached: Bool {
        lock.lock()
        defer { lock.unlock() }
        return detached
    }

    // StandardMessageCodec represents Dart's null option fields as NSNull.
    private func clean(_ value: Any?) -> Any? {
        if let dictionary = value as? [String: Any] {
            return dictionary.compactMapValues { clean($0) }
        }
        if let list = value as? [Any] { return list.map { clean($0) ?? NSNull() } }
        return value is NSNull ? nil : value
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        lock.lock()
        detached = true
        lock.unlock()
        channel?.setMethodCallHandler(nil)
        channel = nil
        let pending = Array(replies.values)
        replies.removeAll()
        queuedBytes = 0
        for reply in pending {
            reply(FlutterError(code: "ENGINE_DETACHED", message: "Flutter engine is detached", details: nil))
        }
        // Drain active decoder work before releasing assets and private files.
        worker.async { [backend] in backend.cleanup() }
    }
}
