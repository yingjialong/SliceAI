@preconcurrency import AVFoundation
import Foundation
import OSLog

/// 本地 TTS 请求模型。
public struct TTSRequest: Sendable, Equatable {
    /// 要朗读的文本。
    public let text: String
    /// 可选系统 voice identifier 或 voice name。
    public let voice: String?

    /// 构造 TTS 请求。
    /// - Parameters:
    ///   - text: 要朗读的文本。
    ///   - voice: 可选系统 voice identifier 或 voice name。
    public init(text: String, voice: String?) {
        self.text = text
        self.voice = voice
    }
}

/// 本地 TTS capability。
public protocol TTSCapability: Sendable {
    /// 朗读给定文本。
    /// - Parameters:
    ///   - text: 要朗读的文本。
    ///   - voice: 可选系统 voice identifier 或 voice name。
    func speak(_ text: String, voice: String?) async throws
}

/// 底层语音合成器边界，供生产 AVFoundation 实现和测试替身共用。
protocol SpeechSynthesizing: Sendable {
    /// 朗读结构化 TTS 请求。
    /// - Parameter request: 朗读请求。
    func speak(_ request: TTSRequest) async throws
}

/// TTS capability 错误。
public enum TTSCapabilityError: Error, Sendable, Equatable {
    /// 朗读文本为空。
    case emptyText
}

/// 基于 AVFoundation 的本地 TTS capability。
public struct AVSpeechTTSCapability: TTSCapability {

    private let synthesizer: any SpeechSynthesizing
    private let logger = Logger(subsystem: "com.sliceai.app", category: "tts")

    /// 构造生产 TTS capability。
    public init() {
        self.synthesizer = AVFoundationSpeechSynthesizer()
    }

    /// 构造可注入底层合成器的 TTS capability。
    /// - Parameter synthesizer: 底层语音合成器。
    init(synthesizer: any SpeechSynthesizing) {
        self.synthesizer = synthesizer
    }

    /// 朗读给定文本。
    /// - Parameters:
    ///   - text: 要朗读的文本。
    ///   - voice: 可选系统 voice identifier 或 voice name。
    public func speak(_ text: String, voice: String?) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TTSCapabilityError.emptyText
        }

        logger.debug(
            "tts speak requested length=\(text.count, privacy: .public) voiceSet=\((voice != nil), privacy: .public)"
        )
        try await synthesizer.speak(TTSRequest(text: text, voice: voice))
    }
}

/// AVFoundation 语音合成器封装。
final class AVFoundationSpeechSynthesizer: SpeechSynthesizing, @unchecked Sendable {

    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "com.sliceai.app", category: "tts")

    /// 构造系统语音合成器。
    init() {}

    /// 在主线程提交朗读请求。
    /// - Parameter request: 朗读请求。
    func speak(_ request: TTSRequest) async throws {
        await MainActor.run {
            let utterance = AVSpeechUtterance(string: request.text)
            if let requestedVoice = request.voice {
                utterance.voice = Self.resolveVoice(requestedVoice)
                if utterance.voice == nil {
                    logger.info("tts requested voice not found, using system default")
                }
            }
            // 只把文本交给系统语音合成器，不写入日志或持久化存储。
            synthesizer.speak(utterance)
        }
    }

    /// 根据 identifier 或展示名解析系统 voice。
    /// - Parameter value: voice identifier 或 voice name。
    /// - Returns: 匹配到的系统 voice；找不到时返回 nil。
    private static func resolveVoice(_ value: String) -> AVSpeechSynthesisVoice? {
        if let voice = AVSpeechSynthesisVoice(identifier: value) {
            return voice
        }
        return AVSpeechSynthesisVoice.speechVoices().first { voice in
            voice.name == value || voice.identifier == value
        }
    }
}
