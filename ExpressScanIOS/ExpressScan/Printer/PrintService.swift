import UIKit

/// 快速排版：没选模板时按当前输入现场排一张
/// （安卓 SimpleLabel 的等价实现——条码占上部固定比例，剩下全给文字，字号按空间最大化）
enum QuickLabel {

    private static let margin: CGFloat = 2

    static func build(paper: LabelPaper,
                      code: String,
                      extras: [String],
                      barcode: BarcodeStyle,
                      barcodeRatio: CGFloat = 0.40) -> LabelTemplate {
        let w = max(CGFloat(paper.wMm), 10)
        let h = max(CGFloat(paper.hMm), 10)
        let innerW = max(w - margin * 2, 4)

        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let extraLines = extras.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var elements: [LabelElement] = []
        var y = margin

        // 条码区
        let canCode = !text.isEmpty && barcode != .none && encodable(text, style: barcode)
        if canCode {
            let barH = min(max(h * barcodeRatio, 5), h * 0.62)
            let e = LabelElement(
                type: barcode == .qrcode ? .CODE_QR : .CODE_BARCODE,
                xMm: Double(margin), yMm: Double(y),
                wMm: Double(innerW), hMm: Double(barH)
            )
            var withData = e
            withData.data = ElementData()
            withData.data.kind = .FIXED
            withData.data.value = text
            elements.append(withData)
            y += barH + 0.5
        }

        // 文字区
        let remainH = max(h - y - margin, 3)
        let codeLines = max(text.isEmpty ? 1 : text.components(separatedBy: "\n").count, 1)

        if extraLines.isEmpty {
            if !text.isEmpty {
                var e = LabelElement(
                    type: .CODE_TEXT, xMm: Double(margin), yMm: Double(y),
                    wMm: Double(innerW), hMm: Double(remainH)
                )
                e.fontMm = Double(min(remainH / CGFloat(codeLines) * 0.66, 10))
                e.bold = true
                e.align = .CENTER
                e.data = ElementData()
                e.data.value = text
                elements.append(e)
            }
        } else {
            let codeH = remainH * 0.55
            let extraH = max(remainH - codeH, 2)

            if !text.isEmpty {
                var e = LabelElement(
                    type: .CODE_TEXT, xMm: Double(margin), yMm: Double(y),
                    wMm: Double(innerW), hMm: Double(codeH)
                )
                e.fontMm = Double(min(codeH / CGFloat(codeLines) * 0.68, 8))
                e.bold = true
                e.align = .CENTER
                e.data = ElementData()
                e.data.value = text
                elements.append(e)
            }

            var e = LabelElement(
                type: .CUSTOM_TEXT, xMm: Double(margin), yMm: Double(y + codeH),
                wMm: Double(innerW), hMm: Double(extraH)
            )
            e.text = extraLines.joined(separator: "\n")
            e.fontMm = Double(min(extraH / CGFloat(extraLines.count) * 0.72, 6))
            e.align = .CENTER
            e.data = ElementData()
            e.data.value = e.text
            elements.append(e)
        }

        return LabelTemplate(
            id: "quick",
            name: "快速排版",
            widthMm: paper.wMm,
            heightMm: paper.hMm,
            elements: elements
        )
    }

    /// Code128 只能吃 ASCII（中文会编码失败），二维码能吃任意 UTF-8 但过长会密到扫不出
    static func encodable(_ text: String, style: BarcodeStyle) -> Bool {
        switch style {
        case .none:
            return false
        case .code128:
            guard (1...48).contains(text.count) else { return false }
            return text.unicodeScalars.allSatisfy { (32...126).contains(Int($0.value)) }
        case .qrcode:
            return (1...200).contains(text.count)
        }
    }
}

/// 打印执行入口：手动打印与扫码自动打印共用，保证输出一致
final class PrintService {
    static let shared = PrintService()

    private let printer = BLEPrinter.shared
    private let store = PrinterStore.shared
    private let templates = LabelTemplateStore.shared

    private init() {}

    /// 本次要用的模板：选了自定义模板就用它，否则快速排版
    func currentTemplate(code: String, extras: [String]) -> LabelTemplate {
        if let t = templates.selected { return t }
        return QuickLabel.build(paper: store.paper, code: code, extras: extras, barcode: store.barcode)
    }

    func print(code: String,
               extras: [String] = [],
               completion: @escaping (Result<Void, Error>) -> Void) {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            completion(.failure(NSError(domain: "ExpressScan", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "没有可打印的内容"])))
            return
        }
        guard printer.ready else {
            completion(.failure(BLEPrintError.notConnected))
            return
        }

        let template = currentTemplate(code: text, extras: extras)
        let spec = PrintSpec(code: text, packageSize: store.packageSize, serial: store.nextSerial())
        let image = LabelRenderer.render(template, spec: spec)

        let data = LabelCommandBuilder.build(
            image: image,
            proto: store.protocolMode,
            density: store.density,
            speed: store.speed,
            copies: store.copies,
            gapMm: 2
        )
        guard !data.isEmpty else {
            completion(.failure(NSError(domain: "ExpressScan", code: 2,
                                        userInfo: [NSLocalizedDescriptionKey: "标签渲染失败"])))
            return
        }

        // CPCL 自带份数字段；TSPL 没有，重复发送同样份数
        if store.protocolMode == .tspl && store.copies > 1 {
            sendRepeated(data, times: store.copies, completion: completion)
        } else {
            printer.send(data) { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    /// 测试页：打一张样张，用来验证走纸与对位
    func printTest(completion: @escaping (Result<Void, Error>) -> Void) {
        print(code: "TEST0123456789", completion: completion)
    }

    private func sendRepeated(_ data: Data, times: Int,
                              completion: @escaping (Result<Void, Error>) -> Void) {
        var left = max(times, 1)

        func next() {
            guard left > 0 else {
                completion(.success(()))
                return
            }
            left -= 1
            printer.send(data) { error in
                if let error {
                    completion(.failure(error))
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { next() }
                }
            }
        }
        next()
    }
}
