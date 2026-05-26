import SliceCore
import XCTest
@testable import Capabilities

/// 本地 TTS capability 测试。
final class TTSCapabilityTests: XCTestCase {

    /// TTS side effect 必须声明 systemAudio 权限。
    func test_ttsSideEffect_requiresSystemAudioPermission() throws {
        XCTAssertEqual(SideEffect.tts(voice: nil).inferredPermissions, [.systemAudio])
    }

    /// 本地 TTS capability 必须把文本和 voice 传给底层合成器。
    func test_localTTS_speaksProvidedFinalText() async throws {
        let synthesizer = SpySpeechSynthesizer()
        let capability = AVSpeechTTSCapability(synthesizer: synthesizer)

        try await capability.speak("Read this", voice: "Alex")

        let requests = await synthesizer.requests
        XCTAssertEqual(requests, [
            TTSRequest(text: "Read this", voice: "Alex")
        ])
    }

    /// Mock TTS capability 必须记录请求且不触发真实发声。
    func test_mockTTS_recordsRequests() async throws {
        let capability = MockTTSCapability()

        try await capability.speak("Preview", voice: nil)

        let requests = await capability.requests
        XCTAssertEqual(requests, [
            TTSRequest(text: "Preview", voice: nil)
        ])
    }
}

/// 测试用底层语音合成器。
private actor SpySpeechSynthesizer: SpeechSynthesizing {
    private(set) var requests: [TTSRequest] = []

    /// 记录朗读请求。
    func speak(_ request: TTSRequest) async throws {
        requests.append(request)
    }
}
