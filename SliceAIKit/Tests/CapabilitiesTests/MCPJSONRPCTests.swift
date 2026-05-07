import Foundation
import SliceCore
import XCTest
@testable import Capabilities

/// MCP JSON-RPC framing 的 wire contract 测试。
final class MCPJSONRPCTests: XCTestCase {

    /// initialize 请求必须编码为 JSON-RPC 2.0 request，并保留结构化 params。
    func test_jsonRPCRequest_encodesInitialize() throws {
        let request = MCPJSONRPCRequest(
            id: 1,
            method: "initialize",
            params: .object([
                "protocolVersion": .string("2025-06-18"),
                "capabilities": .object(["tools": .object([:])]),
                "clientInfo": .object([
                    "name": .string("SliceAI"),
                    "version": .string("0.3.0"),
                ]),
            ])
        )

        let data = try JSONEncoder.sortedForTests.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        let clientInfo = try XCTUnwrap(params["clientInfo"] as? [String: Any])

        XCTAssertEqual(object["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(object["id"] as? Int, 1)
        XCTAssertEqual(object["method"] as? String, "initialize")
        XCTAssertEqual(params["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual(clientInfo["name"] as? String, "SliceAI")
    }

    /// tools/list 响应必须解码为透明 inputSchema，不能把 schema 压扁成字符串字典。
    func test_jsonRPCResponse_decodesToolList() throws {
        let data = Data(#"""
        {
          "jsonrpc": "2.0",
          "id": 2,
          "result": {
            "tools": [
              {
                "name": "echo",
                "title": "Echo Query",
                "description": "Echo query",
                "inputSchema": {
                  "type": "object",
                  "properties": {
                    "query": { "type": "string" }
                  },
                  "required": ["query"]
                }
              },
              {
                "name": "fallback",
                "description": "Fallback title",
                "inputSchema": { "type": "object" }
              }
            ]
          }
        }
        """#.utf8)

        let response = try JSONDecoder().decode(MCPJSONRPCResponse<MCPToolsListResult>.self, from: data)
        let result = try response.resultOrThrow()
        let tool = try XCTUnwrap(result.tools.first)
        let fallbackTool = try XCTUnwrap(result.tools.dropFirst().first)

        XCTAssertEqual(tool.name, "echo")
        XCTAssertEqual(tool.description, "Echo query")
        XCTAssertEqual(tool.descriptor(serverID: "fixture").title, "Echo Query")
        XCTAssertEqual(fallbackTool.descriptor(serverID: "fixture").title, "fallback")
        XCTAssertEqual(tool.inputSchema["type"], .string("object"))
        XCTAssertEqual(
            tool.inputSchema["properties"],
            .object(["query": .object(["type": .string("string")])])
        )
        XCTAssertEqual(tool.inputSchema["required"], .array([.string("query")]))
    }

    /// JSON-RPC error 是协议/传输错误；tools/call result.isError 是工具执行错误，必须作为结果返回。
    func test_jsonRPCError_isSeparatedFromToolExecutionError() throws {
        let rpcErrorData = Data(#"""
        {
          "jsonrpc": "2.0",
          "id": 3,
          "error": { "code": -32601, "message": "Method not found" }
        }
        """#.utf8)
        let rpcError = try JSONDecoder().decode(MCPJSONRPCResponse<MCPCallResult>.self, from: rpcErrorData)
        XCTAssertThrowsError(try rpcError.resultOrThrow()) { error in
            XCTAssertEqual(error as? MCPClientError, .protocolError(code: -32601, message: "Method not found"))
        }

        let toolErrorData = Data(#"""
        {
          "jsonrpc": "2.0",
          "id": 4,
          "result": {
            "content": [{ "type": "text", "text": "tool failed" }],
            "isError": true
          }
        }
        """#.utf8)
        let toolError = try JSONDecoder().decode(MCPJSONRPCResponse<MCPCallResult>.self, from: toolErrorData)
        let result = try toolError.resultOrThrow()

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.content, [.text("tool failed")])
    }
}

private extension JSONEncoder {
    /// 测试专用稳定 JSONEncoder，避免字典顺序影响断言。
    static var sortedForTests: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
