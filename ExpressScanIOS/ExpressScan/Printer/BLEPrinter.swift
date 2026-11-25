import Combine
import CoreBluetooth
import Foundation

/// 扫描到的打印机
struct DiscoveredPrinter: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

enum BLEPrintError: LocalizedError {
    case notConnected
    case noWritableChannel
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected: return "打印机未连接"
        case .noWritableChannel: return "打印机没有可写入的数据通道"
        case .timeout: return "发送超时，请靠近打印机重试"
        }
    }
}

/// 蓝牙打印机连接（BLE）。
///
/// 为什么用 BLE 而不是经典蓝牙 SPP：iOS 上的 SPP 只对 MFi 认证配件开放，
/// 汉印 HM-A300 是「蓝牙 3.0 + BLE 双模」，官方 SDK 也提供 iOS 版，
/// 因此走 BLE 数据通道即可绕开 MFi 限制。
/// 协议层只负责把整页位图字节流按 MTU 分包写进去，与安卓端的分块发送等价。
final class BLEPrinter: NSObject, ObservableObject {
    static let shared = BLEPrinter()

    @Published private(set) var devices: [DiscoveredPrinter] = []
    @Published private(set) var isScanning = false
    @Published private(set) var ready = false
    @Published private(set) var connectedName = ""
    @Published private(set) var statusText = "未连接"

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writable: CBCharacteristic?
    private var peripherals: [UUID: CBPeripheral] = [:]

    private var queue: [Data] = []
    private var writeType: CBCharacteristicWriteType = .withResponse
    private var sending = false
    private var finish: ((Error?) -> Void)?

    private let defaults = UserDefaults.standard
    private let savedUUIDKey = "printerPeripheralUUID"
    private let savedNameKey = "printerPeripheralName"

    override init() {
        super.init()
    }

    // MARK: - 对外接口

    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn && peripheral == nil {
            autoConnectSaved()
        }
    }

    func startScan() {
        guard let central, central.state == .poweredOn else { return }
        devices.removeAll()
        isScanning = true
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        statusText = "正在搜索打印机…"
    }

    func stopScan() {
        central?.stopScan()
        isScanning = false
    }

    func connect(_ device: DiscoveredPrinter) {
        guard let central, let p = peripherals[device.id] else { return }
        stopScan()
        peripheral = p
        p.delegate = self
        statusText = "正在连接 \(device.name)…"
        central.connect(p, options: nil)
    }

    func disconnect() {
        guard let central, let p = peripheral else { return }
        central.cancelPeripheralConnection(p)
        peripheral = nil
        writable = nil
        ready = false
        connectedName = ""
        statusText = "未连接"
    }

    /// 发送一整段打印数据；按 MTU 自动分包，全部写完才算成功
    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        guard let p = peripheral, let ch = writable, p.state == .connected else {
            completion(BLEPrintError.notConnected)
            return
        }

        writeType = ch.properties.contains(.write) ? .withResponse : .withoutResponse
        let maxLen = p.maximumWriteValueLength(for: writeType)
        let chunkSize = max(20, min(maxLen, 480))

        queue.removeAll()
        var index = 0
        while index < data.count {
            let end = min(index + chunkSize, data.count)
            queue.append(data.subdata(in: index..<end))
            index = end
        }

        finish = completion
        sending = true
        pump()
    }

    // MARK: - 分包发送

    private func pump() {
        guard sending, let p = peripheral, let ch = writable else { return }
        guard !queue.isEmpty else {
            sending = false
            let done = finish
            finish = nil
            done?(nil)
            return
        }

        let chunk = queue.removeFirst()
        p.writeValue(chunk, for: ch, type: writeType)

        // 无响应模式没有回调，只能按节奏推进，给打印机留出消费缓冲的时间
        if writeType == .withoutResponse {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.pump()
            }
        }
    }

    private func autoConnectSaved() {
        guard let central else { return }
        guard let saved = defaults.string(forKey: savedUUIDKey),
              let uuid = UUID(uuidString: saved),
              let p = central.retrievePeripherals(withIdentifiers: [uuid]).first else {
            startScan()
            return
        }
        peripheral = p
        p.delegate = self
        statusText = "正在连接 \(defaults.string(forKey: savedNameKey) ?? "打印机")…"
        central.connect(p, options: nil)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEPrinter: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusText = "蓝牙已就绪"
            autoConnectSaved()
        case .poweredOff:
            statusText = "蓝牙未打开，请到设置里打开蓝牙"
            ready = false
        case .unauthorized:
            statusText = "蓝牙权限被拒绝，请到设置里允许"
            ready = false
        case .unsupported:
            statusText = "这台设备不支持蓝牙"
            ready = false
        default:
            statusText = "蓝牙暂不可用"
            ready = false
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? ""
        guard !name.isEmpty else { return }

        peripherals[peripheral.identifier] = peripheral
        if !devices.contains(where: { $0.id == peripheral.identifier }) {
            devices.append(DiscoveredPrinter(id: peripheral.identifier, name: name, rssi: RSSI.intValue))
        }

        // 上次用过的打印机一出现就自动连上，不用每次手动点
        if let saved = defaults.string(forKey: savedUUIDKey),
           saved == peripheral.identifier.uuidString,
           self.peripheral == nil {
            connect(DiscoveredPrinter(id: peripheral.identifier, name: name, rssi: RSSI.intValue))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        statusText = "已连接，正在初始化…"
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        ready = false
        statusText = "连接失败，请靠近打印机重试"
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        ready = false
        writable = nil
        connectedName = ""
        statusText = "已断开"
        if let e = error { statusText = "连接断开：\(e.localizedDescription)" }

        // 正在发送时掉线：把这次打印判为失败，别让界面一直等
        if sending {
            sending = false
            queue.removeAll()
            let done = finish
            finish = nil
            done?(error ?? BLEPrintError.notConnected)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEPrinter: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            statusText = "读取打印机服务失败：\(error.localizedDescription)"
            return
        }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for ch in service.characteristics ?? [] {
            guard ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse) else { continue }
            writable = ch
            ready = true
            connectedName = peripheral.name ?? "打印机"
            statusText = "已连接 \(connectedName)"
            defaults.set(peripheral.identifier.uuidString, forKey: savedUUIDKey)
            defaults.set(connectedName, forKey: savedNameKey)
            stopScan()
            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            sending = false
            queue.removeAll()
            let done = finish
            finish = nil
            done?(error)
            return
        }
        pump()
    }
}
