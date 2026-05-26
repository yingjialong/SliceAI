# Windowing 模块说明

## 模块定位

`Windowing` 是 SliceAI 的 macOS UI 面板模块，负责浮条、命令面板、结果面板、气泡面板、结构化结果视图和屏幕边界定位。该模块不直接执行 LLM 或 MCP，只暴露 UI 组件给 App target 装配。

## 当前功能

- `FloatingToolbarPanel`：划词后展示 PopClip 风格工具栏。
- `CommandPalettePanel`：`⌥Space` 触发的命令面板。
- `ResultPanel`：流式 Markdown 结果、Agent tool-call lifecycle、错误态、复制和重新生成。
- `BubblePanel`：`.bubble` DisplayMode 的 final text 自动消失气泡。
- `StructuredResultView`：`.structured` DisplayMode 的 JSON object 字段渲染。
- `ScreenAwarePositioner`：根据选区锚点和屏幕可视区域计算面板位置。

## DisplayMode UI 行为

- `.window`：执行开始时打开 `ResultPanel`，LLM chunk 通过 `WindowSinkProtocol` 追加到 Markdown 视图。
- `.bubble`：执行开始时不打开 `ResultPanel`；finish 后由 `BubblePanel` 展示完整 final text，并自动隐藏。
- `.structured`：执行开始时打开 `ResultPanel` 展示等待态和 tool-call lifecycle；finish 后解析顶层 JSON object，并切换到 `StructuredResultView`。
- `.replace` / `.file` / `.silent`：Windowing 不直接参与主输出；失败时 AppDelegate 会打开 `ResultPanel` 展示错误。

## 结构化结果

`StructuredResultParser` 要求 final text 是顶层 JSON object，并把字段转换为 `StructuredField` / `StructuredValue`：

- `string`
- `number`
- `bool`
- `array`
- `object`
- `null`

字段按 key 排序，保证测试和 UI 渲染稳定。解析失败由 App 层 `StructuredOutputSink` 转成受控 `SliceError`，避免把 Foundation 原始异常直接展示给用户。

## 验证

当前覆盖：

- `WindowingTests.StructuredResultViewStateTests`：structured JSON 解析和 bubble 自动隐藏纯状态。
- `WindowingTests.ResultPanelToolCallStateTests`：ResultPanel tool-call lifecycle 状态。
- `WindowingTests.ScreenAwarePositionerTests`：屏幕边界定位。
