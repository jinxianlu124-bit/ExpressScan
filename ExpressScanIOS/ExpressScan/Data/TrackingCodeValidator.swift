import Foundation

/// 快递单号校验：拦截「扫错」的内容——商品条码、二维码里的文字/网址、店内码、残码、乱码等。
/// 规则与安卓端 `TrackingCodeValidator.kt` 完全一致，两端判定结果对齐。
///
/// 1. 硬性排除：空、过短、过长、含中文、含空格换行、含网址、含特殊符号、全同字符；
/// 2. EAN / UPC 系列制式基本都是商品条码，直接判疑似；
/// 3. 国际邮政（EA123456789CN）、字母前缀单号（SF/YT/JT/JD…）放行；
/// 4. 纯数字：8–9 位疑似商品码；10–24 位放行，但 69 开头 13 位、0/1 开头 12 位判疑似；
/// 5. 其它字母数字混合：数字不足 8 位判疑似。
enum TrackingCodeValidator {

    enum Verdict {
        /// 通过校验，可以入库
        case ok
        /// 疑似扫错，默认不入库；关联原因用于提示
        case suspect(String)
    }

    /// 合法的单号字符集：字母、数字、连字符（部分单号带 -）
    private static let allowedChars = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")

    /// 字母前缀 + 数字：SF1234567890123 / YT1234567890123 / JD0123456789 …
    private static let alphaPrefix = try! NSRegularExpression(pattern: "^[A-Za-z]{2,4}[0-9]{8,18}$")

    /// 国际邮政：EA123456789CN / CP123456789CN
    private static let intlPost = try! NSRegularExpression(pattern: "^[A-Za-z]{2}[0-9]{9}[A-Za-z]{2}$")

    /// 校验一条扫码结果。
    /// - Parameters:
    ///   - raw: 扫码得到的原始内容
    ///   - format: 条码制式（AVFoundation 返回，如 CODE_128 / EAN_13）
    static func check(_ raw: String, format: String = "") -> Verdict {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // ---- 1. 硬性排除 ----
        if code.isEmpty { return .suspect("内容为空") }
        if code.count < 8 { return .suspect("仅 \(code.count) 位，疑似店内码或残码") }
        if code.count > 32 { return .suspect("长度 \(code.count) 位，疑似文字内容") }

        let lower = code.lowercased()
        if lower.contains("://") || lower.hasPrefix("http") || lower.contains("www.") {
            return .suspect("这是网址，不是快递单号")
        }
        if code.unicodeScalars.contains(where: isCJK) { return .suspect("含中文，疑似文字内容") }
        if code.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return .suspect("含空格或换行，疑似多行内容")
        }
        if code.unicodeScalars.contains(where: { !allowedChars.contains($0) }) {
            return .suspect("含特殊符号，疑似其它条码内容")
        }
        if Set(code).count == 1 { return .suspect("全为同一字符，疑似乱码") }

        // ---- 2. 制式提示：EAN / UPC 系列基本都是商品条码 ----
        let fmt = format.uppercased()
        if ["EAN_13", "EAN_8", "UPC_A", "UPC_E"].contains(fmt) {
            return .suspect("识别为商品条码（\(format)），不是快递单号")
        }

        // ---- 3. 邮政与字母前缀单号 ----
        if matches(intlPost, code) { return .ok }
        if matches(alphaPrefix, code) { return .ok }

        // ---- 4. 纯数字 ----
        if code.allSatisfy({ $0.isNumber }) {
            switch code.count {
            case 8...9:
                return .suspect("仅 \(code.count) 位数字，疑似商品条码或店内码")
            case 10...24:
                // 中国商品条码固定以 690–699 开头（13 位）
                if code.count == 13 && code.hasPrefix("69") {
                    return .suspect("69 开头 13 位，疑似商品条码")
                }
                if code.count == 12 && (code.hasPrefix("0") || code.hasPrefix("1")) {
                    return .suspect("12 位 UPC 商品码，疑似商品条码")
                }
                return .ok
            default:
                return .suspect("数字位数异常（\(code.count) 位）")
            }
        }

        // ---- 5. 其它字母数字混合：至少 8 位数字才当单号 ----
        let digitCount = code.filter { $0.isNumber }.count
        if digitCount < 8 { return .suspect("数字仅 \(digitCount) 位，疑似非快递单号") }
        return .ok
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value)
            || (0x3400...0x4DBF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
    }
}

/// 扫码页本地设置：是否开启单号校验（与安卓 ScanPrefs 同名同义）
enum ScanPrefs {
    private static let key = "scan_validate_code"

    /// 默认开启：拦截疑似非快递单号的内容
    static var validateCode: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
