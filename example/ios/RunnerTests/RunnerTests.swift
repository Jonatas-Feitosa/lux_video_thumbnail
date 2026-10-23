import Flutter
import XCTest
@testable import lux_video_thumbnail_ios

final class RunnerTests: XCTestCase {
    func testTimestampNormalizationAndMicroseconds() throws {
        XCTAssertEqual(try ThumbnailPolicy.timestamp(["timestampUs": 1234567], durationMs: 2000), 1234567)
        XCTAssertEqual(try ThumbnailPolicy.timestamp(["timestampMs": 2000], durationMs: 2000), 1999999)
        XCTAssertEqual(try ThumbnailPolicy.timestamp(["timestampUs": 1234567], durationMs: nil), 1234567)
        XCTAssertThrowsError(try ThumbnailPolicy.timestamp(["timestampUs": -1], durationMs: nil))
        XCTAssertThrowsError(try ThumbnailPolicy.timestamp(["timestampMs": 2001], durationMs: 2000))
    }

    func testGeometryAndValidation() throws {
        let size = try ThumbnailPolicy.outputSize(["width": 160, "height": 160], width: 1920, height: 1080)
        XCTAssertEqual(size.0, 160)
        XCTAssertEqual(size.1, 90)
        XCTAssertThrowsError(try ThumbnailPolicy.validate(["format": "webp"]))
        XCTAssertThrowsError(try ThumbnailPolicy.validate(["width": 4097]))
        XCTAssertThrowsError(try ThumbnailPolicy.integer(true, "offset"))
        XCTAssertThrowsError(try ThumbnailPolicy.integer(1.5, "offset"))
    }

    func testOnlyOwnedThumbnailFilesCanBeAccessed() throws {
        let files = OwnedTemporaryFiles()
        defer { files.cleanup() }
        let input = try files.create(input: true, extension: "mp4")
        let thumbnail = try files.create(input: false, extension: "jpg")
        XCTAssertThrowsError(try files.thumbnail(input.path))
        XCTAssertThrowsError(try files.deleteThumbnail(input.path))
        XCTAssertEqual(try files.thumbnail(thumbnail.path), thumbnail)
        try files.deleteThumbnail(thumbnail.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnail.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
        files.deleteInput(input)
        XCTAssertFalse(FileManager.default.fileExists(atPath: input.path))
    }

    func testWorkerRepliesOnMainThread() {
        let plugin = LuxVideoThumbnailPlugin()
        let done = expectation(description: "worker reply")
        plugin.handle(FlutterMethodCall(methodName: "getPlatformVersion", arguments: nil)) { response in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue((response as? String)?.hasPrefix("iOS ") == true)
            done.fulfill()
        }
        waitForExpectations(timeout: 5)
    }
}
