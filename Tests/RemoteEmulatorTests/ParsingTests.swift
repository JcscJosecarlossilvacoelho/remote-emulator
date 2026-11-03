import XCTest
@testable import RemoteEmulator

final class ParsingTests: XCTestCase {
    func testRuntimeVersion() {
        XCTAssertEqual(DeviceService.runtimeVersion("com.apple.CoreSimulator.SimRuntime.iOS-26-5"), "iOS 26.5")
        XCTAssertEqual(DeviceService.runtimeVersion("com.apple.CoreSimulator.SimRuntime.iOS-18-2"), "iOS 18.2")
    }

    func testAgentSelector() {
        let sim = Device(id: "ABC-123", name: "iPhone 17 Pro", platform: .ios, osVersion: "iOS 26.5", state: .booted)
        XCTAssertEqual(sim.agentSelector, "--platform ios --udid ABC-123")

        var emulator = Device(id: "Pixel_9_Pro", name: "Pixel 9 Pro", platform: .android, osVersion: "Android 16", state: .shutdown)
        XCTAssertEqual(emulator.agentSelector, "--platform android --device Pixel_9_Pro")
        emulator.serial = "emulator-5554"
        XCTAssertEqual(emulator.agentSelector, "--platform android --serial emulator-5554")
    }

    func testDeviceSymbols() {
        XCTAssertEqual(Device(id: "1", name: "iPad Air", platform: .ios, osVersion: "", state: .shutdown).symbol, "ipad")
        XCTAssertEqual(Device(id: "2", name: "iPhone 17", platform: .ios, osVersion: "", state: .shutdown).symbol, "iphone")
    }

    func testExpoAppLoadsIdentifiers() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"name":"pkg","dependencies":{"expo":"~58.0.0"}}"#
            .write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try #"{"expo":{"name":"My App","ios":{"bundleIdentifier":"com.example.app"},"android":{"package":"com.example.android"}}}"#
            .write(to: dir.appendingPathComponent("app.json"), atomically: true, encoding: .utf8)

        let app = try XCTUnwrap(ExpoApp.load(from: dir))
        XCTAssertEqual(app.name, "My App")
        XCTAssertEqual(app.bundleIdentifier, "com.example.app")
        XCTAssertEqual(app.androidPackage, "com.example.android")
        XCTAssertEqual(app.sdkVersion, "~58.0.0")
    }

    func testExpoAppRequiresPackageJSON() {
        XCTAssertNil(ExpoApp.load(from: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")))
    }
}
