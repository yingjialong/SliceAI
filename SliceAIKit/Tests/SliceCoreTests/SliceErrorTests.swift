import XCTest
@testable import SliceCore

final class SliceErrorTests: XCTestCase {
    func test_userMessage_forEachCategory() {
        XCTAssertFalse(SliceError.permission(.accessibilityDenied).userMessage.isEmpty)
        XCTAssertFalse(SliceError.selection(.axEmpty).userMessage.isEmpty)
        XCTAssertFalse(SliceError.provider(.unauthorized).userMessage.isEmpty)
        XCTAssertFalse(SliceError.configuration(.fileNotFound).userMessage.isEmpty)
    }

    func test_providerRateLimited_includesRetryAfter() {
        let msg = SliceError.provider(.rateLimited(retryAfter: 30)).userMessage
        XCTAssertTrue(msg.contains("30"))
    }

    func test_developerContext_noSensitive() {
        // developerContext 用于日志，绝不包含 API Key 或选中文字
        let err = SliceError.provider(.unauthorized)
        XCTAssertFalse(err.developerContext.lowercased().contains("sk-"))
    }
}
