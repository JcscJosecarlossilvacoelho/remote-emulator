import XCTest
@testable import RemoteEmulator

final class ControlPathTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("re-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("app"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAllowsRootExistingAndNewFolders() {
        XCTAssertNotNil(ControlService.resolve("", inside: root))
        XCTAssertNotNil(ControlService.resolve("app", inside: root))
        XCTAssertNotNil(ControlService.resolve("new-project/sub", inside: root))
    }

    func testRejectsEscapes() {
        XCTAssertNil(ControlService.resolve("..", inside: root))
        XCTAssertNil(ControlService.resolve("app/../../etc", inside: root))
        XCTAssertNil(ControlService.resolve("/etc", inside: root))
        XCTAssertNil(ControlService.resolve(root.path + "-sibling", inside: root))
    }

    func testRejectsSymlinkOutside() throws {
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertNil(ControlService.resolve("escape", inside: root))
        XCTAssertNil(ControlService.resolve("escape/new", inside: root))
    }
}
