import XCTest
@testable import SliceCore

final class AppSnapshotTests: XCTestCase {

    func test_init_preservesAllFields() {
        let url = URL(string: "https://example.com")
        let snap = AppSnapshot(bundleId: "com.apple.Safari", name: "Safari", url: url, windowTitle: "Example")
        XCTAssertEqual(snap.bundleId, "com.apple.Safari")
        XCTAssertEqual(snap.name, "Safari")
        XCTAssertEqual(snap.url, url)
        XCTAssertEqual(snap.windowTitle, "Example")
    }

    func test_init_allowsNilUrlAndTitle() {
        let snap = AppSnapshot(bundleId: "com.apple.Notes", name: "Notes", url: nil, windowTitle: nil)
        XCTAssertNil(snap.url)
        XCTAssertNil(snap.windowTitle)
    }

    func test_codable_roundtrip() throws {
        let snap = AppSnapshot(
            bundleId: "com.microsoft.VSCode",
            name: "VSCode",
            url: nil,
            windowTitle: "main.swift - SliceAI"
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(AppSnapshot.self, from: data)
        XCTAssertEqual(snap, decoded)
    }
}
