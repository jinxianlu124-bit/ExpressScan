import SwiftUI
import UniformTypeIdentifiers

/// 打印页：顶部「扫码后自动打印」开关 + 当前模板 + 单号输入 + 实时预览 + 打印。
/// 默认按选中的自定义模板出票（版式、字号、条码位置全照模板），没选模板时才走快速排版。
struct PrintView: View {
    @ObservedObject private var printer = BLEPrinter.shared
    @ObservedObject private var store = PrinterStore.shared
    @ObservedObject private var templates = LabelTemplateStore.shared

    @State private var code = ""
    @State private var extra = ""
    @State private var preview: UIImage?
    @State private var printing = false
    @State private var showDevices = false
    @State private var showTemplates = false
    @State private var showAdvanced = false
    @State private var showImporter = false
    @State private var toast: String?

    private var extraLines: [String] { extra.components(separatedBy: "\n") }

    /// 参与预览刷新的所有输入
    private var previewKey: String {
        "\(code)|\(extra)|\(store.paper.rawValue)|\(store.barcode.rawValue)|\(templates.selectedId)|\(templates.imported.count)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    autoPrintCard
                    deviceCard
                    templateCard
                    inputCard
                    if templates.selected == nil {
                        optionsCard
                    }
                    previewCard
                }
                .padding(16)
                .padding(.bottom, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("打印")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdvanced = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { printBar }
            .task { printer.start() }
            .task(id: previewKey) { renderPreview() }
            .sheet(isPresented: $showDevices) { deviceSheet }
            .sheet(isPresented: $showTemplates) { templateSheet }
            .sheet(isPresented: $showAdvanced) { advancedSheet }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.footnote)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 80)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: toast)
            .task(id: toast) {
                guard toast != nil else { return }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                toast = nil
            }
        }
    }

    // MARK: - 自动打印（置顶）

    private var autoPrintCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("扫码后自动打印").font(.headline)
                Text(store.autoPrint ? "已开启：扫到新单号立即出票" : "已关闭：扫码只入库，想打再点打印")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $store.autoPrint).labelsHidden()
        }
        .padding(14)
        .background(store.autoPrint ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 打印机

    private var deviceCard: some View {
        Button {
            showDevices = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "printer")
                    .font(.title3)
                    .foregroundStyle(printer.ready ? Color.accentColor : Color(.secondaryLabel))
                VStack(alignment: .leading, spacing: 3) {
                    Text(printer.ready ? printer.connectedName : "未连接打印机")
                        .font(.subheadline).bold()
                        .foregroundStyle(.primary)
                    Text(printer.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(printer.ready ? "更换" : "连接")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 模板

    private var templateCard: some View {
        Button {
            showTemplates = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("模板：\(templates.selected?.name ?? "快速排版")")
                        .font(.subheadline).bold()
                        .foregroundStyle(.primary)
                    Text(templateSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("更换").font(.subheadline).foregroundStyle(Color.accentColor)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var templateSubtitle: String {
        if let t = templates.selected {
            return "\(t.widthMm)×\(t.heightMm)mm · \(t.elements.count) 个元素 · 按模板出票"
        }
        return "未选择模板，按输入内容自动排版"
    }

    // MARK: - 输入

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("快递单号（也可输入任意文字）", text: $code, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !code.isEmpty {
                    Button {
                        code = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()

            if templates.selected == nil {
                TextField("附加文字（可选，每行一条）", text: $extra, axis: .vertical)
                    .lineLimit(2...4)
            } else {
                Text("当前用模板出票：单号、条码、文字的位置与内容都由模板决定，附加文字不生效")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 条码 / 纸张（仅快速排版生效）

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("条码").font(.caption).foregroundStyle(.secondary)
            Picker("条码", selection: $store.barcode) {
                ForEach(BarcodeStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)

            if !code.isEmpty && store.barcode != .none && !QuickLabel.encodable(code, style: store.barcode) {
                Text(store.barcode == .code128
                     ? "这段内容含中文或超长，一维码无法编码，本次只打文字。需要条码请改成「二维码」"
                     : "内容过长，二维码可能扫不出来，建议精简")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Text("标签纸尺寸").font(.caption).foregroundStyle(.secondary)
            Picker("纸张", selection: $store.paper) {
                ForEach(LabelPaper.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 预览

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("打印预览").font(.subheadline).bold()
                Spacer()
                Text(previewSizeText).font(.caption).foregroundStyle(.secondary)
            }
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("输入单号后这里会实时显示打印效果")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var previewSizeText: String {
        if let t = templates.selected { return "\(t.widthMm)×\(t.heightMm)mm" }
        return store.paper.displayName
    }

    // MARK: - 底部打印栏

    private var printBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    store.copies = max(store.copies - 1, 1)
                } label: {
                    Image(systemName: "minus").frame(width: 30, height: 30)
                }
                .disabled(store.copies <= 1)

                Text("\(store.copies)").font(.headline).frame(minWidth: 22)

                Button {
                    store.copies = min(store.copies + 1, 99)
                } label: {
                    Image(systemName: "plus").frame(width: 30, height: 30)
                }
                .disabled(store.copies >= 99)
            }
            .buttonStyle(.bordered)

            Button {
                doPrint()
            } label: {
                HStack(spacing: 6) {
                    if printing {
                        ProgressView().tint(.white)
                        Text("正在打印…")
                    } else {
                        Image(systemName: "printer.fill")
                        Text(store.copies > 1 ? "打印 ×\(store.copies)" : "打印")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(printing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - 设备弹窗

    private var deviceSheet: some View {
        NavigationStack {
            List {
                if printer.ready {
                    Section("当前连接") {
                        HStack {
                            Text(printer.connectedName)
                            Spacer()
                            Button("断开", role: .destructive) { printer.disconnect() }
                        }
                    }
                }
                Section("附近的打印机") {
                    if printer.devices.isEmpty {
                        Text(printer.isScanning ? "正在搜索…" : "没有搜索到设备，点右上角重新搜索")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(printer.devices) { d in
                        Button {
                            printer.connect(d)
                            showDevices = false
                        } label: {
                            HStack {
                                Text(d.name).foregroundStyle(.primary)
                                Spacer()
                                Text("\(d.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择打印机")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { showDevices = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(printer.isScanning ? "搜索中…" : "重新搜索") { printer.startScan() }
                        .disabled(printer.isScanning)
                }
            }
            .onAppear {
                printer.start()
                if printer.devices.isEmpty { printer.startScan() }
            }
        }
    }

    // MARK: - 模板弹窗

    private var templateSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        templates.select("")
                        showTemplates = false
                    } label: {
                        HStack {
                            Text("快速排版").foregroundStyle(.primary)
                            Spacer()
                            if templates.selected == nil {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                } footer: {
                    Text("按输入内容自动排版：条码 + 单号 + 附加文字")
                }

                Section("内置模板") {
                    ForEach(LabelTemplateStore.builtIn) { t in
                        templateRow(t)
                    }
                }

                if !templates.imported.isEmpty {
                    Section("已导入") {
                        ForEach(templates.imported) { t in
                            templateRow(t)
                        }
                        .onDelete { indexSet in
                            indexSet.map { templates.imported[$0] }.forEach { templates.delete($0) }
                        }
                    }
                }

                Section {
                    Button("从文件导入模板 JSON") { showImporter = true }
                } footer: {
                    Text("模板 JSON 与安卓端字段完全一致（w/h/elements…），同一份文件两边都能用。")
                }
            }
            .navigationTitle("选择模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { showTemplates = false }
                }
            }
            // 模板选择页自己持有文件选择器，避免从已弹出的 sheet 里再弹不出东西
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
        }
    }

    private func templateRow(_ t: LabelTemplate) -> some View {
        Button {
            templates.select(t.id)
            showTemplates = false
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name).foregroundStyle(.primary)
                    Text("\(t.widthMm)×\(t.heightMm)mm · \(t.elements.count) 个元素")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if templates.selectedId == t.id {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    // MARK: - 高级设置

    private var advancedSheet: some View {
        NavigationStack {
            Form {
                Section("打印协议") {
                    Picker("协议", selection: $store.protocolMode) {
                        ForEach(PrinterProtocol.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(store.protocolMode.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("浓度与速度") {
                    Stepper("浓度 \(store.density)（字浅 / 条码扫不出就调高）", value: $store.density, in: 1...15)
                    Stepper("速度 \(store.speed)", value: $store.speed, in: 1...5)
                }

                Section {
                    Button("打印测试页") { testPrint() }
                    Button("重置序号") {
                        store.resetSerial()
                        toast = "序号已重置为 0001"
                    }
                } footer: {
                    Text("测试页会打一张样张，用来确认走纸与对位是否正确。")
                }
            }
            .navigationTitle("高级设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showAdvanced = false }
                }
            }
        }
    }

    // MARK: - 行为

    private func renderPreview() {
        let template = PrintService.shared.currentTemplate(code: code, extras: extraLines)
        let spec = PrintSpec(code: code, packageSize: store.packageSize, serial: "0001")
        preview = LabelRenderer.preview(template, spec: spec)
    }

    private func doPrint() {
        guard !printing else { return }
        printing = true
        PrintService.shared.print(code: code, extras: extraLines) { result in
            printing = false
            switch result {
            case .success:
                toast = store.copies > 1 ? "已发送打印 ×\(store.copies)" : "已发送打印"
            case .failure(let error):
                toast = "打印失败：\(error.localizedDescription)"
            }
        }
    }

    private func testPrint() {
        guard !printing else { return }
        printing = true
        PrintService.shared.printTest { result in
            printing = false
            switch result {
            case .success: toast = "测试页已发送"
            case .failure(let error): toast = "打印失败：\(error.localizedDescription)"
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let count = templates.importFile(url)
            if count > 0 {
                showTemplates = false
                toast = "已导入 \(count) 个模板"
            } else {
                toast = "文件里没有可识别的模板"
            }
        case .failure(let error):
            toast = "导入失败：\(error.localizedDescription)"
        }
    }
}
