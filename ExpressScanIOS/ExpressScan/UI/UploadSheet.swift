import SwiftData
import SwiftUI

/// 上传腾讯文档弹窗：首次创建表格，之后追加到同一份表格。
struct UploadSheet: View {
    let records: [ScanRecord]
    var onDone: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var token: String
    @State private var showTokenField = false
    @State private var uploading = false
    @State private var error: String?

    private static let tokenKey = "tdocs.access_token"
    private static let sheetRefKey = "tdocs.sheet_ref"

    init(records: [ScanRecord], onDone: @escaping (String) -> Void) {
        self.records = records
        self.onDone = onDone
        let stored = UserDefaults.standard.string(forKey: Self.tokenKey)
        _token = State(initialValue: stored ?? TencentDocsUploader.defaultAccessToken)
    }

    private var existingRef: SheetRef? {
        guard let json = UserDefaults.standard.string(forKey: Self.sheetRefKey),
              let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(SheetRef.self, from: data)
    }

    private var usingDefaultToken: Bool {
        (UserDefaults.standard.string(forKey: Self.tokenKey) ?? TencentDocsUploader.defaultAccessToken)
            == TencentDocsUploader.defaultAccessToken
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(existingRef == nil
                         ? "首次上传将创建一份在线表格；之后每次上传自动追加到同一份表格，不再重复新建。"
                         : "将把 \(records.count) 条记录追加到已有表格（不新建）。")
                    Text("Token：" + (usingDefaultToken ? "使用内置 Token（约 2026-11-23 过期）" : "已保存自定义 Token"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Token 设置") {
                    if !showTokenField {
                        Button("修改 Token") { showTokenField = true }
                    } else {
                        TextField("粘贴 access_token", text: $token)
                            .font(.footnote)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        Button("恢复内置 Token") {
                            token = TencentDocsUploader.defaultAccessToken
                            showTokenField = false
                            error = nil
                        }
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("上传到腾讯文档")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if uploading {
                        ProgressView()
                    } else {
                        Button("上传") { Task { await upload() } }
                            .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func upload() async {
        uploading = true
        defer { uploading = false }
        error = nil

        UserDefaults.standard.set(token, forKey: Self.tokenKey)

        do {
            let uploader = try TencentDocsUploader(accessToken: token)
            let headers = ["运单号", "条码制式", "扫码时间"]
            let rows = records.map { [$0.code, $0.format, $0.exportTime] }
            let (ref, url) = try await uploader.uploadRows(
                title: "ExpressScan 扫码记录",
                headers: headers,
                dataRows: rows,
                existing: existingRef
            )
            if let data = try? JSONEncoder().encode(ref) {
                UserDefaults.standard.set(String(data: data, encoding: .utf8), forKey: Self.sheetRefKey)
            }
            let verb = existingRef == nil ? "已创建表格并写入" : "已追加"
            await MainActor.run {
                dismiss()
                onDone("\(verb) \(records.count) 条：\(url)")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
