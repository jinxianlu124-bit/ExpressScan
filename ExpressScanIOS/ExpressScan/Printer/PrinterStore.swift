import Combine
import Foundation

/// 标签纸规格（与安卓 LabelPaper 一致）
enum LabelPaper: String, CaseIterable, Identifiable {
    case p30x20
    case p40x30
    case p40x60
    case p50x30
    case p60x40

    var id: String { rawValue }

    var wMm: Int {
        switch self {
        case .p30x20: return 30
        case .p40x30, .p40x60: return 40
        case .p50x30: return 50
        case .p60x40: return 60
        }
    }

    var hMm: Int {
        switch self {
        case .p30x20: return 20
        case .p40x30, .p50x30: return 30
        case .p40x60: return 60
        case .p60x40: return 40
        }
    }

    var displayName: String { "\(wMm)×\(hMm)mm" }
}

/// 条码类型
enum BarcodeStyle: String, CaseIterable, Identifiable {
    case code128
    case qrcode
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .code128: return "一维码"
        case .qrcode: return "二维码"
        case .none: return "不打印条码"
        }
    }
}

/// 打印配置（UserDefaults 持久化，键名与安卓端语义对齐）
final class PrinterStore: ObservableObject {
    static let shared = PrinterStore()

    @Published var paper: LabelPaper { didSet { save(paper.rawValue, .paper) } }
    @Published var barcode: BarcodeStyle { didSet { save(barcode.rawValue, .barcode) } }
    @Published var copies: Int { didSet { save(copies, .copies) } }
    @Published var density: Int { didSet { save(density, .density) } }
    @Published var speed: Int { didSet { save(speed, .speed) } }
    @Published var autoPrint: Bool { didSet { save(autoPrint, .autoPrint) } }
    @Published var protocolMode: PrinterProtocol { didSet { save(protocolMode.rawValue, .protocolMode) } }
    @Published var packageSize: String { didSet { save(packageSize, .packageSize) } }

    private let defaults = UserDefaults.standard

    private enum Keys: String {
        case paper, barcode, copies, density, speed, autoPrint, protocolMode, packageSize, serial
    }

    private init() {
        // 局部变量取值：Swift 要求所有存储属性赋完值之前不能碰 self
        let d = UserDefaults.standard

        paper = LabelPaper(rawValue: d.string(forKey: Keys.paper.rawValue) ?? "") ?? .p40x30
        barcode = BarcodeStyle(rawValue: d.string(forKey: Keys.barcode.rawValue) ?? "") ?? .code128
        copies = max(d.integer(forKey: Keys.copies.rawValue), 1)

        let densityRaw = d.integer(forKey: Keys.density.rawValue)
        density = densityRaw == 0 ? 8 : min(max(densityRaw, 1), 15)

        let speedRaw = d.integer(forKey: Keys.speed.rawValue)
        speed = speedRaw == 0 ? 2 : min(max(speedRaw, 1), 5)

        autoPrint = d.bool(forKey: Keys.autoPrint.rawValue)
        protocolMode = PrinterProtocol(rawValue: d.string(forKey: Keys.protocolMode.rawValue) ?? "") ?? .cpcl
        packageSize = d.string(forKey: Keys.packageSize.rawValue) ?? ""
    }

    private func save(_ value: Any, _ key: Keys) {
        defaults.set(value, forKey: key.rawValue)
    }

    /// 序号：每打一张自增，模板里的流水号组件用它
    func nextSerial() -> String {
        let next = max(defaults.integer(forKey: Keys.serial.rawValue), 1)
        defaults.set(next + 1, forKey: Keys.serial.rawValue)
        return String(format: "%04d", next)
    }

    func resetSerial() {
        defaults.set(1, forKey: Keys.serial.rawValue)
    }
}
