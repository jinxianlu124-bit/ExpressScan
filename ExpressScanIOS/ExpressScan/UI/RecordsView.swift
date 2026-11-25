import SwiftData
import SwiftUI

/// 记录页：「本次记录」与「全部历史」双视图 + 上传/复制/删除。
struct RecordsView: View {
    /// 由扫码页「查看历史记录」驱动：true 时直接打开全部历史。
    @Binding var showHistory: Bool

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var allRecords: [ScanRecord]

    @State private var sessionStart: Date?
    @State private var query = ""
    @State private var selected = Set<PersistentIdentifier>()
    @State private var showDeleteConfirm = false
    @State private var showUpload = false
    @State private var toast: String?

    /// 当前视图的数据源
    private var source: [ScanRecord] {
        guard !showHistory else { return allRecords }
        guard let start = sessionStart else { return [] }
        return allRecords.filter { $0.createdAt >= start }
    }

    private var filtered: [ScanRecord] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard showHistory, !keyword.isEmpty else { return source }
        return source.filter {
            $0.code.localizedCaseInsensitiveContains(keyword)
                || $0.format.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var allSelected: Bool {
        !filtered.isEmpty && filtered.allSatisfy { selected.contains($0.persistentModelID) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 视图切换
            HStack(spacing: 8) {
                chip(title: "本次记录", active: !showHistory) {
                    showHistory = false
                    selected.removeAll()
                }
                chip(title: "全部历史", active: showHistory) {
                    showHistory = true
                    selected.removeAll()
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if showHistory {
                TextField("搜索历史记录（运单号 / 制式）", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text(emptyText)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(filtered) { record in
                    RecordRow(
                        record: record,
                        selected: selected.contains(record.persistentModelID),
                        onToggle: { toggle(record) }
                    )
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("复制") { copy([record]) }.tint(.blue)
                        Button("删除", role: .destructive) {
                            selected = [record.persistentModelID]
                            showDeleteConfirm = true
                        }
                    }
                }
                .listStyle(.plain)
                .animation(.default, value: filtered.count)
            }

            // 底部中文操作栏
            HStack {
                Button(allSelected ? "取消全选" : "全选") { toggleAll() }
                    .disabled(filtered.isEmpty)
                Spacer()
                Button("复制") { copy(selectedRecords()) }
                    .disabled(selected.isEmpty)
                Spacer()
                Button("删除") { showDeleteConfirm = true }
                    .disabled(selected.isEmpty)
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showUpload = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(selected.isEmpty)
            }
        }
        .onAppear { sessionStart = ScanSession.currentSessionStart() }
        .sheet(isPresented: $showUpload) {
            UploadSheet(records: selectedRecords()) { message in
                showUpload = false
                selected.removeAll()
                toast = message
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) { deleteSelected() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所选 \(selected.count) 条记录，删除后不可恢复。确定继续吗？")
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 20)
            }
        }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            toast = nil
        }
    }

    // MARK: - 子视图

    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(active ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(active ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        showHistory ? "全部历史（\(filtered.count)/\(allRecords.count)）" : "本次记录（\(source.count)）"
    }

    private var emptyText: String {
        if !showHistory {
            return "本次还没有扫码记录\n（超过 5 分钟未扫码或重启 App 后，记录会自动归入历史）"
        }
        return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "暂无历史记录，去「扫码」页扫一个快递条码吧"
            : "未找到匹配的记录"
    }

    // MARK: - 操作

    private func toggle(_ record: ScanRecord) {
        let id = record.persistentModelID
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func toggleAll() {
        if allSelected {
            selected.removeAll()
        } else {
            selected = Set(filtered.map { $0.persistentModelID })
        }
    }

    private func selectedRecords() -> [ScanRecord] {
        allRecords.filter { selected.contains($0.persistentModelID) }
    }

    private func copy(_ records: [ScanRecord]) {
        let text = records.map { $0.code }.joined(separator: "\n")
        UIPasteboard.general.string = text
        toast = "已复制 \(records.count) 条到剪贴板"
    }

    private func deleteSelected() {
        let targets = selectedRecords()
        targets.forEach { modelContext.delete($0) }
        try? modelContext.save()
        selected.removeAll()
        toast = "已删除 \(targets.count) 条记录"
    }
}

private struct RecordRow: View {
    let record: ScanRecord
    let selected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.code).font(.body)
                    Text("\(record.format) · \(record.displayTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RecordsView(showHistory: .constant(false))
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
