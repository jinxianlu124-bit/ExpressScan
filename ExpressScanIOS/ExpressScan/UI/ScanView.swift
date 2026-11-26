import AVFoundation
import SwiftData
import SwiftUI

/// 扫码页：半屏相机预览 + 连续识别，结果落入当前扫码会话。
struct ScanView: View {
    /// 点击「查看历史记录」时切到记录页的历史视图。
    var onOpenHistory: () -> Void

    @Environment(\.modelContext) private var modelContext
    @StateObject private var camera = CameraController()
    @State private var batchMode = true
    @State private var authorized = false
    @State private var permissionDenied = false
    @State private var paused = false
    @State private var lastText: String?
    @State private var toast: String?
    /// 是否开启「防止扫错单号」（与安卓 ScanPrefs 同名，默认开）
    @State private var validateCode = ScanPrefs.validateCode
    /// 被拦下的疑似内容，非空时弹确认框
    @State private var suspicious: SuspiciousCode?

    /// 疑似扫错的一条：给用户看清楚内容，再决定要不要硬存
    private struct SuspiciousCode: Identifiable {
        let id = UUID()
        let code: String
        let format: String
        let reason: String
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // 上半屏：相机取景器（约 45%）
                ZStack {
                    if authorized {
                        CameraPreview(session: camera.session)
                    } else {
                        Color.black
                        VStack(spacing: 12) {
                            Text(permissionDenied ? "相机权限被拒绝" : "正在获取相机权限…")
                                .foregroundStyle(.white)
                            if permissionDenied {
                                Button("去设置开启") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                .frame(height: geo.size.height * 0.45)
                .clipped()
                // 手电筒：暗处扫面单用，只有带补光灯的机型才显示
                .overlay(alignment: .topTrailing) {
                    if authorized && camera.torchAvailable {
                        Button {
                            camera.toggleTorch()
                        } label: {
                            Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(camera.torchOn ? Color.black : Color.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle().fill(camera.torchOn ? Color.yellow : Color.black.opacity(0.45))
                                )
                        }
                        .accessibilityLabel(camera.torchOn ? "关闭手电筒" : "打开手电筒")
                        .padding(.top, 14)
                        .padding(.trailing, 14)
                    }
                }

                // 下半屏：控制区
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("批量扫码（连续识别）", isOn: $batchMode)
                        .padding(.top, 12)

                    Toggle("防止扫错单号", isOn: $validateCode)
                        .onChange(of: validateCode) { _, newValue in
                            ScanPrefs.validateCode = newValue
                        }

                    Text(validateCode
                         ? "商品条码 / 网址 / 乱码会被拦下，不入库（可单次放行）"
                         : "已关闭：扫到什么就存什么")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let lastText {
                        Text("最近识别：\(lastText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text(batchMode ? "批量模式：对准条码即可连续录入，2 秒内同码自动去重"
                                   : "单次模式：识别一条后自动暂停，点「继续扫描」再扫下一个")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !batchMode && paused {
                        Button("继续扫描") {
                            paused = false
                            camera.start()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("识别结果保存到「记录」页；完整历史永久保留，可随时查询")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("查看历史记录") { onOpenHistory() }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 6)

                    Spacer()
                }
                .padding(.horizontal, 16)
            }
        }
        .onAppear(perform: checkPermission)
        .onDisappear { camera.stop() }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: toast)
        .alert("疑似不是快递单号",
               isPresented: Binding(get: { suspicious != nil },
                                    set: { if !$0 { suspicious = nil } }),
               presenting: suspicious) { item in
            Button("仍要保存") {
                let code = item.code
                let format = item.format
                suspicious = nil
                save(code, format: format)
            }
            Button("忽略", role: .cancel) { suspicious = nil }
        } message: { item in
            Text("\(item.reason)\n\n\(item.code)")
        }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            toast = nil
        }
    }

    // MARK: - 权限

    private func checkPermission() {
        camera.onDetect = handleScan
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
            camera.start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    authorized = granted
                    permissionDenied = !granted
                    if granted { camera.start() }
                }
            }
        default:
            permissionDenied = true
        }
    }

    // MARK: - 识别处理

    private func handleScan(code: String, format: String) {
        lastText = "\(code)（\(format)）"

        // 1) 2 秒内同码去重：不重复入库，提示「已扫码」
        let since = Date().addingTimeInterval(-2)
        let predicate = #Predicate<ScanRecord> { record in
            record.createdAt > since && record.code == code
        }
        let descriptor = FetchDescriptor<ScanRecord>(predicate: predicate)
        let duplicated = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard duplicated == 0 else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            toast = "已扫码：\(code)"
            return
        }

        // 2) 防止扫错单号：商品条码 / 网址 / 乱码等拦下，交用户决定
        if validateCode, case let .suspect(reason) = TrackingCodeValidator.check(code, format: format) {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            suspicious = SuspiciousCode(code: code, format: format, reason: reason)
            return
        }

        save(code, format: format)
    }

    /// 真正入库（正常识别与「仍要保存」都走这里）
    private func save(_ code: String, format: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        ScanSession.onScan()
        modelContext.insert(ScanRecord(code: code, format: format))
        try? modelContext.save()

        // 扫码后自动打印（开关在打印页顶部；未连接打印机时静默跳过）
        if PrinterStore.shared.autoPrint {
            DispatchQueue.main.async {
                PrintService.shared.print(code: code) { _ in }
            }
        }

        // 单次模式：录入一条后暂停，需手动继续
        if !batchMode {
            paused = true
            camera.stop()
        }

        toast = "已记录：\(code)"
    }
}
