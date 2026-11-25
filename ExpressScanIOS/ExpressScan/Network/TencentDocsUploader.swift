import Foundation

/// 已创建表格的引用：持久化后后续上传直接追加到同一份表格。
struct SheetRef: Codable {
    let fileID: String
    let sheetID: String
    let url: String
}

enum TencentDocsError: LocalizedError {
    case invalidToken(String)
    case business(ret: Int, action: String, hint: String)
    case badResponse(action: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidToken(let message):
            return "Token 无效：\(message)"
        case .business(let ret, let action, let hint):
            return "\(action)失败 ret=\(ret)：\(hint)"
        case .badResponse(let action, let detail):
            return "\(action)响应异常：\(detail)"
        }
    }
}

/// 腾讯文档上传器（Swift 版，接口与 Android 版一致）。
///
/// 链路（全部为智能表 smartsheet）：
/// 1. 创建文档 POST /openapi/drive/v2/files
/// 2. 查子表   GET  /openapi/smartbook/v2/files/{fileID}/sheets
/// 3. 建字段   POST /openapi/smartbook/v2/files/{fileID}/sheets/{sheetID}  body: addFields
/// 4. 写记录   POST 同一路径                                                body: addRecords
///
/// 鉴权三头缺一不可：Access-Token / Client-Id（JWT 的 clt）/ Open-Id（JWT 的 sub）。
final class TencentDocsUploader {
    /// 内置默认 token（与 Android 版相同，约 2026-11-23 过期，可在 App 内替换为新 token）。
    static let defaultAccessToken =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJjbHQiOiJlY2EzZDlhOWY1OTM0YzAyOTVlNmZiMWJkOTEyOWRkNyIsInR5cCI6MSwiZXhwIjoxNzk1Mzc1NzI2LjM3NDk3OSwiaWF0IjoxNzkyNzgzNzI2LjM3NDk3OSwic3ViIjoiMWU3OGZlMjFlN2RkNGE2MjgwYmUwZjg4Zjk1ZDc5MmQifQ.2yVF80OUwss_4DZ64E9L6ftj2s4tHd0nMbmrnqrBdrY"

    private static let fieldTypeText = 1

    private let accessToken: String
    private let clientID: String
    private let openID: String

    init(accessToken: String) throws {
        self.accessToken = accessToken
        let payload = try Self.decodeJWTPayload(accessToken)
        guard let clt = payload["clt"] as? String, !clt.isEmpty,
              let sub = payload["sub"] as? String, !sub.isEmpty
        else {
            throw TencentDocsError.invalidToken("不是有效的腾讯文档 JWT（缺少 clt/sub 字段），请重新获取")
        }
        clientID = clt
        openID = sub
    }

    /// 追加式上传：有旧引用时追加，失败则自动新建表格。
    func uploadRows(
        title: String,
        headers: [String],
        dataRows: [[String]],
        existing: SheetRef?
    ) async throws -> (SheetRef, String) {
        guard !dataRows.isEmpty else { throw TencentDocsError.invalidToken("没有可写入的数据") }

        if let existing {
            do {
                try await addRecords(fileID: existing.fileID, sheetID: existing.sheetID,
                                     headers: headers, dataRows: dataRows)
                return (existing, existing.url)
            } catch {
                // 旧表格失效（删除/权限变更）时降级为新建
                print("[TencentDocs] 追加失败，改为新建：\(error.localizedDescription)")
            }
        }

        let (fileID, url) = try await createSmartsheet(title: title)
        let sheetID = try await firstSheetID(fileID: fileID)
        try await addFields(fileID: fileID, sheetID: sheetID, headers: headers)
        try await addRecords(fileID: fileID, sheetID: sheetID, headers: headers, dataRows: dataRows)
        return (SheetRef(fileID: fileID, sheetID: sheetID, url: url), url)
    }

    // MARK: - 四步链路

    private func createSmartsheet(title: String) async throws -> (String, String) {
        let json = try await call(
            path: "/openapi/drive/v2/files",
            method: "POST",
            body: ["type": "smartsheet", "title": title],
            action: "创建文档"
        )
        guard let data = json["data"] as? [String: Any],
              let id = data["ID"] as? String, !id.isEmpty,
              let url = data["url"] as? String, !url.isEmpty
        else {
            throw TencentDocsError.badResponse(action: "创建文档", detail: "响应缺少 ID/url")
        }
        return (id, url)
    }

    private func firstSheetID(fileID: String) async throws -> String {
        let json = try await call(
            path: "/openapi/smartbook/v2/files/\(fileID)/sheets",
            method: "GET",
            body: nil,
            action: "查询子表"
        )
        guard let data = json["data"] as? [String: Any],
              let sheets = data["getSheet"] as? [[String: Any]],
              let sheetID = sheets.first?["sheetID"] as? String, !sheetID.isEmpty
        else {
            throw TencentDocsError.badResponse(action: "查询子表", detail: "文档中没有可用子表")
        }
        return sheetID
    }

    private func addFields(fileID: String, sheetID: String, headers: [String]) async throws {
        let fields: [[String: Any]] = headers.map {
            ["fieldTitle": $0, "fieldType": Self.fieldTypeText]
        }
        _ = try await call(
            path: "/openapi/smartbook/v2/files/\(fileID)/sheets/\(sheetID)",
            method: "POST",
            body: ["addFields": ["fields": fields]],
            action: "创建字段"
        )
    }

    private func addRecords(
        fileID: String,
        sheetID: String,
        headers: [String],
        dataRows: [[String]]
    ) async throws {
        var records: [[String: Any]] = []
        for row in dataRows {
            var values: [String: Any] = [:]
            for (index, header) in headers.enumerated() {
                let text = index < row.count ? row[index] : ""
                // 智能表要求单元格值为 [{type,text}] 数组结构，裸字符串会导致写入后值为空
                values[header] = [["type": "text", "text": text]]
            }
            records.append(["values": values])
        }
        _ = try await call(
            path: "/openapi/smartbook/v2/files/\(fileID)/sheets/\(sheetID)",
            method: "POST",
            body: ["addRecords": ["records": records]],
            action: "写入记录"
        )
    }

    // MARK: - 网络与鉴权

    private func call(
        path: String,
        method: String,
        body: [String: Any]?,
        action: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: "https://docs.qq.com\(path)") else {
            throw TencentDocsError.badResponse(action: action, detail: "URL 非法")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(accessToken, forHTTPHeaderField: "Access-Token")
        request.setValue(clientID, forHTTPHeaderField: "Client-Id")
        request.setValue(openID, forHTTPHeaderField: "Open-Id")
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TencentDocsError.badResponse(action: action, detail: "非 HTTP 响应")
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        guard http.statusCode == 200 else {
            throw TencentDocsError.business(
                ret: http.statusCode, action: action, hint: String(text.prefix(300))
            )
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TencentDocsError.badResponse(action: action, detail: String(text.prefix(300)))
        }
        let ret = json["ret"] as? Int ?? -1
        guard ret == 0 else {
            let hint: String
            switch ret {
            case 10313: hint = "Access-Token 校验失败（token 为空或格式错误）"
            case 10302: hint = "Client-Id 校验失败（token 可能不完整）"
            case 10303: hint = "Open-Id 校验失败（token 可能不完整）"
            case 37019: hint = "token 已过期或无效，请重新获取"
            default: hint = (json["msg"] as? String) ?? "未知错误"
            }
            throw TencentDocsError.business(ret: ret, action: action, hint: hint)
        }
        return json
    }

    private static func decodeJWTPayload(_ token: String) throws -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            throw TencentDocsError.invalidToken("格式不是 JWT")
        }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw TencentDocsError.invalidToken("payload 解码失败")
        }
        return json
    }
}
