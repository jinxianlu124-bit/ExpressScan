import Combine
import Foundation

// MARK: - 组件类型

/// 标签组件类型。名称与安卓端 `ElementType` 完全一致，
/// 因此安卓导出的 `label_templates.json` 可以直接拿来用（见 LabelTemplateStore.importFile）。
enum ElementType: String, Codable, CaseIterable {
    case CODE_BARCODE
    case CODE_QR
    case CODE_TEXT
    case SIZE_TEXT
    case DATE_TEXT
    case CUSTOM_TEXT
    case SERIAL_TEXT
    case LINE
    case RECT
    case IMAGE

    var displayName: String {
        switch self {
        case .CODE_BARCODE: return "单号条码"
        case .CODE_QR: return "单号二维码"
        case .CODE_TEXT: return "单号文字"
        case .SIZE_TEXT: return "包裹尺寸"
        case .DATE_TEXT: return "打印时间"
        case .CUSTOM_TEXT: return "文字"
        case .SERIAL_TEXT: return "序号"
        case .LINE: return "线条"
        case .RECT: return "矩形"
        case .IMAGE: return "图片"
        }
    }

    var isText: Bool {
        switch self {
        case .CODE_TEXT, .SIZE_TEXT, .DATE_TEXT, .CUSTOM_TEXT, .SERIAL_TEXT: return true
        default: return false
        }
    }
}

enum TextAlign: String, Codable {
    case LEFT
    case CENTER
    case RIGHT

    var displayName: String {
        switch self {
        case .LEFT: return "左对齐"
        case .CENTER: return "居中"
        case .RIGHT: return "右对齐"
        }
    }
}

/// 数据来源：固定数据 / 流水号 / 日期时间（与安卓 ElementData.kind 对应）
enum DataKind: String, Codable {
    case FIXED
    case SERIAL
    case DATETIME
}

// MARK: - 数据源

struct ElementData: Codable {
    var kind: DataKind = .FIXED
    /// 固定数据内容；流水号时作前缀
    var value: String = ""
    var serialStart: Int = 1
    var serialStep: Int = 1
    var suffix: String = ""
    var datePattern: String = "yyyy-MM-dd HH:mm"

    init() {}

    enum CodingKeys: String, CodingKey {
        case kind, value, serialStart, serialStep, suffix, datePattern
    }

    /// 容错解码：安卓端的旧模板可能缺字段，缺了就用默认值，不能整份模板读不出来
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kindRaw = (try? c.decode(String.self, forKey: .kind)) ?? ""
        kind = DataKind(rawValue: kindRaw) ?? .FIXED
        value = (try? c.decode(String.self, forKey: .value)) ?? ""
        serialStart = (try? c.decode(Int.self, forKey: .serialStart)) ?? 1
        serialStep = (try? c.decode(Int.self, forKey: .serialStep)) ?? 1
        suffix = (try? c.decode(String.self, forKey: .suffix)) ?? ""
        datePattern = (try? c.decode(String.self, forKey: .datePattern)) ?? "yyyy-MM-dd HH:mm"
    }
}

// MARK: - 组件

/// 一个标签组件。位置与尺寸统一用毫米，渲染时按 203dpi（8 点/毫米）换算。
struct LabelElement: Codable, Identifiable {
    var id: String = UUID().uuidString
    var type: ElementType = .CUSTOM_TEXT
    var text: String = ""
    var xMm: Double = 2
    var yMm: Double = 2
    var wMm: Double = 36
    var hMm: Double = 8
    /// 字高（毫米），仅文字类有效
    var fontMm: Double = 3
    var bold: Bool = false
    var align: TextAlign = .CENTER
    /// 0 / 90 / 180 / 270
    var rotation: Int = 0
    var imagePath: String = ""
    var data: ElementData = ElementData()

    init() {}

    init(type: ElementType, text: String = "", xMm: Double, yMm: Double,
         wMm: Double, hMm: Double, fontMm: Double = 3, bold: Bool = false,
         align: TextAlign = .CENTER) {
        self.type = type
        self.text = text
        self.xMm = xMm
        self.yMm = yMm
        self.wMm = wMm
        self.hMm = hMm
        self.fontMm = fontMm
        self.bold = bold
        self.align = align
    }

    enum CodingKeys: String, CodingKey {
        case id, type, text, xMm, yMm, wMm, hMm, fontMm, bold, align, rotation, imagePath, data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        let typeRaw = (try? c.decode(String.self, forKey: .type)) ?? ""
        type = ElementType(rawValue: typeRaw) ?? .CUSTOM_TEXT
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        xMm = (try? c.decode(Double.self, forKey: .xMm)) ?? 2
        yMm = (try? c.decode(Double.self, forKey: .yMm)) ?? 2
        wMm = (try? c.decode(Double.self, forKey: .wMm)) ?? 36
        hMm = (try? c.decode(Double.self, forKey: .hMm)) ?? 8
        fontMm = (try? c.decode(Double.self, forKey: .fontMm)) ?? 3
        bold = (try? c.decode(Bool.self, forKey: .bold)) ?? false
        let alignRaw = (try? c.decode(String.self, forKey: .align)) ?? ""
        align = TextAlign(rawValue: alignRaw) ?? .CENTER
        rotation = (try? c.decode(Int.self, forKey: .rotation)) ?? 0
        imagePath = (try? c.decode(String.self, forKey: .imagePath)) ?? ""
        data = (try? c.decode(ElementData.self, forKey: .data)) ?? ElementData()
    }

    /// 解析本次要打的内容：固定数据优先，其次单号类回落到本次单号
    func resolve(_ spec: PrintSpec) -> String {
        switch data.kind {
        case .FIXED:
            let v = data.value.isEmpty ? text : data.value
            if !v.isEmpty { return v }
            switch type {
            case .CODE_TEXT, .CODE_BARCODE, .CODE_QR:
                return spec.code
            case .SIZE_TEXT:
                return spec.packageSize.isEmpty ? "" : "尺寸 \(spec.packageSize)"
            case .DATE_TEXT:
                // 没配数据源的时间组件：默认按「打印时间」出，不然会打成空白
                let f = DateFormatter()
                f.locale = Locale(identifier: "zh_CN")
                f.dateFormat = data.datePattern
                return f.string(from: spec.time)
            default:
                return ""
            }
        case .SERIAL:
            var digits = spec.serial
            while digits.hasPrefix("0") { digits.removeFirst() }
            let base = max(Int(digits) ?? 1, 1)
            let n = data.serialStart + (base - 1) * data.serialStep
            return data.value + String(n) + data.suffix
        case .DATETIME:
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = data.datePattern
            return f.string(from: spec.time)
        }
    }
}

// MARK: - 模板

struct LabelTemplate: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = "未命名模板"
    var widthMm: Int = 40
    var heightMm: Int = 30
    var elements: [LabelElement] = []

    init() {}

    init(id: String = UUID().uuidString, name: String, widthMm: Int, heightMm: Int, elements: [LabelElement]) {
        self.id = id
        self.name = name
        self.widthMm = widthMm
        self.heightMm = heightMm
        self.elements = elements
    }

    /// 与安卓 LabelTemplateStore 的 JSON 字段保持一致（w / h）
    enum CodingKeys: String, CodingKey {
        case id, name, w, h, elements
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "未命名模板"
        widthMm = (try? c.decode(Int.self, forKey: .w)) ?? 40
        heightMm = (try? c.decode(Int.self, forKey: .h)) ?? 30
        elements = (try? c.decode([LabelElement].self, forKey: .elements)) ?? []

        // v1.7 及更早的「比例制」模板：坐标是 0~1 的小数，这里换算成毫米
        if elements.contains(where: { $0.xMm <= 1 && $0.wMm <= 1 }) {
            let w = Double(widthMm)
            let h = Double(heightMm)
            elements = elements.map { e in
                var n = e
                n.xMm = e.xMm * w
                n.yMm = e.yMm * h
                n.wMm = max(e.wMm * w, 4)
                n.hMm = max(e.hMm * h, 3)
                n.fontMm = max(e.fontMm * h, 2)
                return n
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(widthMm, forKey: .w)
        try c.encode(heightMm, forKey: .h)
        try c.encode(elements, forKey: .elements)
    }
}

// MARK: - 模板库

/// 模板库：内置三套 + 从文件导入（安卓导出的同名字段 JSON 直接可用）。
/// 选中项存 UserDefaults，打印页默认按选中的模板出票。
final class LabelTemplateStore: ObservableObject {
    static let shared = LabelTemplateStore()

    @Published private(set) var imported: [LabelTemplate] = []
    @Published private(set) var selectedId: String = ""

    private let selectedKey = "selectedTemplateId"
    private let fileName = "label_templates.json"

    private init() {
        selectedId = UserDefaults.standard.string(forKey: selectedKey) ?? ""
        load()
    }

    // MARK: 内置模板

    static let builtIn: [LabelTemplate] = [
        LabelTemplate(
            id: "preset_waybill_40x30",
            name: "运单标签 40×30",
            widthMm: 40,
            heightMm: 30,
            elements: [
                LabelElement(type: .CODE_BARCODE, xMm: 2, yMm: 2, wMm: 36, hMm: 13),
                LabelElement(type: .CODE_TEXT, xMm: 2, yMm: 16, wMm: 36, hMm: 7, fontMm: 4, bold: true),
                LabelElement(type: .SIZE_TEXT, xMm: 2, yMm: 23.5, wMm: 36, hMm: 4.5, fontMm: 2.6),
            ]
        ),
        LabelTemplate(
            id: "preset_waybill_40x60",
            name: "面单标签 40×60",
            widthMm: 40,
            heightMm: 60,
            elements: [
                LabelElement(type: .CUSTOM_TEXT, text: "快递运单", xMm: 2, yMm: 2, wMm: 36, hMm: 6, fontMm: 3.4, bold: true, align: .LEFT),
                LabelElement(type: .CODE_BARCODE, xMm: 2, yMm: 9, wMm: 36, hMm: 22),
                LabelElement(type: .CODE_TEXT, xMm: 2, yMm: 32, wMm: 36, hMm: 9, fontMm: 5, bold: true),
                LabelElement(type: .LINE, xMm: 2, yMm: 42, wMm: 36, hMm: 0.5),
                LabelElement(type: .DATE_TEXT, xMm: 2, yMm: 45, wMm: 36, hMm: 5, fontMm: 2.6, align: .LEFT),
                LabelElement(type: .SIZE_TEXT, xMm: 2, yMm: 51, wMm: 36, hMm: 5, fontMm: 2.6, align: .LEFT),
            ]
        ),
        LabelTemplate(
            id: "preset_storage_50x30",
            name: "货位标签 50×30",
            widthMm: 50,
            heightMm: 30,
            elements: [
                LabelElement(type: .CUSTOM_TEXT, text: "货位 / 库位", xMm: 2, yMm: 1.5, wMm: 32, hMm: 6, fontMm: 3, align: .LEFT),
                LabelElement(type: .CODE_TEXT, xMm: 2, yMm: 7, wMm: 32, hMm: 12, fontMm: 7, bold: true, align: .LEFT),
                LabelElement(type: .CODE_QR, xMm: 35, yMm: 7, wMm: 13, hMm: 13),
                LabelElement(type: .LINE, xMm: 2, yMm: 20, wMm: 46, hMm: 0.6),
                LabelElement(type: .DATE_TEXT, xMm: 2, yMm: 22, wMm: 32, hMm: 5, fontMm: 2.4, align: .LEFT),
            ]
        ),
    ]

    var all: [LabelTemplate] { Self.builtIn + imported }

    /// 当前选中的模板；空字符串 = 用「快速排版」
    var selected: LabelTemplate? {
        guard !selectedId.isEmpty else { return nil }
        return all.first { $0.id == selectedId }
    }

    func select(_ id: String) {
        selectedId = id
        UserDefaults.standard.set(id, forKey: selectedKey)
        objectWillChange.send()
    }

    // MARK: 读写

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(fileName)
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            imported = []
            return
        }
        imported = (try? JSONDecoder().decode([LabelTemplate].self, from: data)) ?? []
    }

    /// 导入一份模板 JSON（数组或单个对象都兼容），返回导入条数
    @discardableResult
    func importFile(_ url: URL) -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return 0 }

        var incoming = (try? JSONDecoder().decode([LabelTemplate].self, from: data)) ?? []
        if incoming.isEmpty, let one = try? JSONDecoder().decode(LabelTemplate.self, from: data) {
            incoming = [one]
        }
        guard !incoming.isEmpty else { return 0 }

        for t in incoming {
            if let idx = imported.firstIndex(where: { $0.id == t.id }) {
                imported[idx] = t
            } else {
                imported.append(t)
            }
        }
        persist()
        if selectedId.isEmpty, let first = incoming.first { select(first.id) }
        return incoming.count
    }

    func delete(_ template: LabelTemplate) {
        imported.removeAll { $0.id == template.id }
        persist()
        if selectedId == template.id { select("") }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(imported) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
