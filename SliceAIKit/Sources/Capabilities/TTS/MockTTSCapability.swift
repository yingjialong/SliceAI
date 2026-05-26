/// 测试和预览用 TTS capability。
public final actor MockTTSCapability: TTSCapability {

    /// 已收到的朗读请求。
    public private(set) var requests: [TTSRequest] = []

    /// 默认构造器。
    public init() {}

    /// 记录朗读请求，不触发真实系统发声。
    /// - Parameters:
    ///   - text: 要朗读的文本。
    ///   - voice: 可选系统 voice identifier 或 voice name。
    public func speak(_ text: String, voice: String?) async throws {
        requests.append(TTSRequest(text: text, voice: voice))
    }

    /// 清空已记录请求。
    public func reset() {
        requests.removeAll()
    }
}
