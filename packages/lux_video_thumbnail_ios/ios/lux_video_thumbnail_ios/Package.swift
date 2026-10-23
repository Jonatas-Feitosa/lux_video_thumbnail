// swift-tools-version: 5.9
import Foundation
import PackageDescription

// Flutter 3.44+ supplies FlutterFramework next to this package. Older Flutter
// versions supply the module through Xcode's framework search paths instead.
let flutterFramework = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("../FlutterFramework")
let hasFlutterFramework = FileManager.default.fileExists(atPath: flutterFramework.path)
let package = Package(
    name: "lux_video_thumbnail_ios",
    platforms: [.iOS(.v13)],
    products: [.library(name: "lux-video-thumbnail-ios", targets: ["lux_video_thumbnail_ios"])],
    dependencies: hasFlutterFramework
        ? [.package(name: "FlutterFramework", path: "../FlutterFramework")] : [],
    targets: [
        .target(
            name: "lux_video_thumbnail_ios",
            dependencies: hasFlutterFramework
                ? [.product(name: "FlutterFramework", package: "FlutterFramework")] : [],
            resources: [.process("PrivacyInfo.xcprivacy")]
        )
    ]
)
