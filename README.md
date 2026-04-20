# SliceAI

> macOS 开源划词触发 LLM 工具栏

SliceAI 让你在任何 Mac 应用里选中文字后，通过快捷工具栏或 `⌥Space` 命令面板调用 OpenAI 兼容的大模型，流式查看结果。

## Status

v0.1 开发中。参见 [docs/superpowers/plans](docs/superpowers/plans/) 跟踪进度。

## Features (MVP v0.1)

- 划词后自动弹出浮条工具栏（PopClip 风格）
- `⌥Space` 快捷键唤起中央命令面板
- 独立浮窗 Markdown 流式渲染
- 支持 OpenAI 兼容协议（OpenAI、DeepSeek、Moonshot、OpenRouter、自建中转…）
- 4 个内置工具：Translate / Polish / Summarize / Explain
- 自定义 prompt、供应商、模型
- API Key 存 macOS Keychain

## Build from source

```bash
git clone https://github.com/<you>/SliceAI.git
cd SliceAI
open SliceAI.xcodeproj
# Product → Run
```

## Requirements

- macOS 14 Sonoma 或更新
- Xcode 26 或更新
- Swift 6.0

## License

MIT — see [LICENSE](LICENSE)
