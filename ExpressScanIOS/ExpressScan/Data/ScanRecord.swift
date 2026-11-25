import Foundation

/// 扫码记录（SwiftData 持久化，数据永久保留）。
@Model
final class ScanRecord {
    var code: String
    var format: String
    var createdAt: Date
    var uploaded: Bool

    init(code: String, format: String, createdAt: Date = .now, uploaded: Bool = false) {
        self.code = code
        self.format = format
        self.createdAt = createdAt
        self.uploaded = uploaded
    }
}

extension ScanRecord {
    /// 「MM-dd HH:mm:ss」格式时间，用于列表展示。
    var displayTime: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: createdAt)
    }

    /// 腾讯文档写入用的标准时间格式。
    var exportTime: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: createdAt)
    }
}
