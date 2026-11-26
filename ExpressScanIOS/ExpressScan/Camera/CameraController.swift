import AVFoundation
import SwiftUI

/// AVFoundation 相机封装：条码识别（CODE128 / CODE39 / QR / EAN 等）。
final class CameraController: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "expressscan.camera")
    private var configured = false
    private var device: AVCaptureDevice?

    /// 设备是否带补光灯（无灯的机型不显示按钮）
    @Published private(set) var torchAvailable = false
    /// 补光灯当前是否点亮
    @Published private(set) var torchOn = false

    /// 识别回调（主线程触发）。
    var onDetect: ((_ code: String, _ format: String) -> Void)?

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.configure()
                self.configured = true
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // 关相机时顺手关灯，避免退出页面后手电筒一直亮着
            if let device = self.device, device.torchMode == .on {
                try? device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.torchOn = false }
            }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    /// 切换补光灯（手电筒）。光线暗的仓库/车厢里扫面单用得上。
    func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                let turnOn = device.torchMode != .on
                if turnOn {
                    try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
                let on = turnOn
                DispatchQueue.main.async { self.torchOn = on }
            } catch {
                DispatchQueue.main.async { self.torchOn = false }
            }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        self.device = device
        let hasTorch = device.hasTorch
        DispatchQueue.main.async { self.torchAvailable = hasTorch }

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        // 只启用设备支持的码制，避免 unsupported 类型导致崩溃
        let wanted: [AVMetadataObject.ObjectType] = [
            .code128, .code39, .code39Mod43, .code93, .qr, .ean13, .ean8, .upce, .pdf417, .itf14,
        ]
        let available = output.availableMetadataObjectTypes
        output.metadataObjectTypes = wanted.filter { available.contains($0) }
        output.setMetadataObjectsDelegate(self, queue: .main)

        session.commitConfiguration()
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue,
              !code.isEmpty
        else { return }
        onDetect?(code, object.type.displayName)
    }
}

extension AVMetadataObject.ObjectType {
    /// 展示用的码制名称，与 Android 版命名保持一致。
    var displayName: String {
        switch self {
        case .code128: return "CODE_128"
        case .code39: return "CODE_39"
        case .code39Mod43: return "CODE_39"
        case .code93: return "CODE_93"
        case .qr: return "QR_CODE"
        case .ean13: return "EAN_13"
        case .ean8: return "EAN_8"
        case .upce: return "UPC_E"
        case .pdf417: return "PDF417"
        case .itf14: return "ITF"
        default: return rawValue
        }
    }
}
