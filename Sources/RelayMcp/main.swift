import Foundation
import RelayMcpCore

/// relay-mcp — 로컬 읽기 전용 MCP 서버 (stdio · newline-delimited JSON-RPC)
@main
struct RelayMcpMain {
    static func main() {
        let store = McpDataStore()
        let stdout = FileHandle.standardOutput

        while let line = readLine(strippingNewline: true) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            guard let response = McpRouter.handle(line: line, store: store) else { continue }
            // 파이프 stdout — synchronizeFile 금지 (NSFileHandleOperationException)
            if let data = (response + "\n").data(using: .utf8) {
                stdout.write(data)
            }
        }
    }
}
