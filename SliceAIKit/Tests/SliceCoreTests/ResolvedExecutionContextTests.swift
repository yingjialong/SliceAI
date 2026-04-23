import XCTest
@testable import SliceCore

final class ResolvedExecutionContextTests: XCTestCase {

    private func makeSeed() -> ExecutionSeed {
        ExecutionSeed(
            invocationId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            selection: SelectionSnapshot(text: "t", source: .accessibility, length: 1, language: nil, contentType: nil),
            frontApp: AppSnapshot(bundleId: "com.apple.Safari", name: "Safari", url: nil, windowTitle: nil),
            screenAnchor: .zero,
            timestamp: Date(timeIntervalSince1970: 50),
            triggerSource: .commandPalette,
            isDryRun: false
        )
    }

    func test_init_preservesAllFields() {
        let seed = makeSeed()
        let key = ContextKey(rawValue: "vocab")
        let rc = ResolvedExecutionContext(
            seed: seed,
            contexts: ContextBag(values: [key: .text("list")]),
            resolvedAt: Date(timeIntervalSince1970: 60),
            failures: [:]
        )
        XCTAssertEqual(rc.seed, seed)
        XCTAssertNotNil(rc.contexts[key])
        XCTAssertTrue(rc.failures.isEmpty)
        XCTAssertEqual(rc.resolvedAt, Date(timeIntervalSince1970: 60))
    }

    func test_transparentAccessors_forwardToSeed() {
        let seed = makeSeed()
        let rc = ResolvedExecutionContext(seed: seed, contexts: ContextBag(values: [:]), resolvedAt: Date(), failures: [:])
        XCTAssertEqual(rc.invocationId, seed.invocationId)
        XCTAssertEqual(rc.selection, seed.selection)
        XCTAssertEqual(rc.frontApp, seed.frontApp)
        XCTAssertEqual(rc.isDryRun, seed.isDryRun)
        XCTAssertEqual(rc.screenAnchor, seed.screenAnchor)
        XCTAssertEqual(rc.triggerTimestamp, seed.timestamp)
        XCTAssertEqual(rc.triggerSource, seed.triggerSource)
    }

    func test_failures_carryOptionalRequestErrors() {
        let seed = makeSeed()
        let key = ContextKey(rawValue: "vocab")
        let err = SliceError.configuration(.fileNotFound)
        let rc = ResolvedExecutionContext(
            seed: seed,
            contexts: ContextBag(values: [:]),
            resolvedAt: Date(),
            failures: [key: err]
        )
        XCTAssertEqual(rc.failures[key]?.userMessage, err.userMessage)
    }

    func test_equality_sameFields_isEqual() {
        let seed = makeSeed()
        let rc1 = ResolvedExecutionContext(seed: seed, contexts: ContextBag(values: [:]), resolvedAt: Date(timeIntervalSince1970: 10), failures: [:])
        let rc2 = ResolvedExecutionContext(seed: seed, contexts: ContextBag(values: [:]), resolvedAt: Date(timeIntervalSince1970: 10), failures: [:])
        XCTAssertEqual(rc1, rc2)
    }

    func test_equality_differentResolvedAt_isNotEqual() {
        let seed = makeSeed()
        let rc1 = ResolvedExecutionContext(
            seed: seed, contexts: ContextBag(values: [:]),
            resolvedAt: Date(timeIntervalSince1970: 10), failures: [:]
        )
        let rc2 = ResolvedExecutionContext(
            seed: seed, contexts: ContextBag(values: [:]),
            resolvedAt: Date(timeIntervalSince1970: 20), failures: [:]
        )
        XCTAssertNotEqual(rc1, rc2)
    }

    func test_equality_differentFailures_isNotEqual() {
        let seed = makeSeed()
        let key = ContextKey(rawValue: "vocab")
        let rc1 = ResolvedExecutionContext(
            seed: seed, contexts: ContextBag(values: [:]),
            resolvedAt: Date(timeIntervalSince1970: 10), failures: [:]
        )
        let rc2 = ResolvedExecutionContext(
            seed: seed, contexts: ContextBag(values: [:]),
            resolvedAt: Date(timeIntervalSince1970: 10),
            failures: [key: .configuration(.fileNotFound)]
        )
        XCTAssertNotEqual(rc1, rc2)
    }
}
