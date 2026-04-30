import LLMProviders
import SliceCore
import XCTest

final class OpenAIProviderFactoryTests: XCTestCase {

    /// 构造测试用 V2Provider。
    /// - Parameters:
    ///   - kind: Provider 协议族。
    ///   - baseURL: Provider endpoint；openAICompatible 必须非 nil。
    /// - Returns: 可传入 OpenAIProviderFactory 的 V2Provider。
    private func makeProvider(
        kind: ProviderKind = .openAICompatible,
        baseURL: URL? = URL(string: "https://example.com/v1") // swiftlint:disable:this force_unwrapping
    ) -> V2Provider {
        V2Provider(
            id: "provider",
            kind: kind,
            name: "Provider",
            baseURL: baseURL,
            apiKeyRef: "keychain:provider",
            defaultModel: "gpt-5",
            capabilities: []
        )
    }

    /// OpenAIProviderFactory 应直接接受合法的 V2Provider。
    func test_make_acceptsOpenAICompatibleV2Provider() throws {
        let factory = OpenAIProviderFactory()

        _ = try factory.make(for: makeProvider(), apiKey: "sk-test")
    }

    /// 非 OpenAI-compatible 协议族必须在 factory 层被拒绝，且错误消息不拼接用户配置。
    func test_make_rejectsUnsupportedKindWithFixedValidationMessage() throws {
        let factory = OpenAIProviderFactory()

        XCTAssertThrowsError(try factory.make(for: makeProvider(kind: .anthropic, baseURL: nil), apiKey: "sk-test")) { error in
            guard case SliceError.configuration(.validationFailed(let message)) = error else {
                XCTFail("expected validationFailed, got \(error)")
                return
            }
            XCTAssertEqual(message, "OpenAIProviderFactory only supports kind=openAICompatible")
        }
    }

    /// openAICompatible 但 baseURL 缺失时必须在 factory 层被拒绝，且错误消息不拼接用户配置。
    func test_make_rejectsOpenAICompatibleNilBaseURLWithFixedValidationMessage() throws {
        let factory = OpenAIProviderFactory()

        XCTAssertThrowsError(try factory.make(for: makeProvider(baseURL: nil), apiKey: "sk-test")) { error in
            guard case SliceError.configuration(.validationFailed(let message)) = error else {
                XCTFail("expected validationFailed, got \(error)")
                return
            }
            XCTAssertEqual(message, "OpenAIProviderFactory requires non-nil baseURL")
        }
    }
}
