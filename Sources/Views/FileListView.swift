import SwiftUI

/// Documents/Output や Documents/Extracted の中身を一覧し、
/// チェックして共有 / 書き出し・削除するための画面。
struct FileListView: View {
    let emptyMessage: String

    /// 一覧しているフォルダ。パス表示にも使うので保持しておく。
    private let directory: URL
    private let locationTitle: String
    private let locationCaption: String

    @StateObject private var model: FileListModel
    @State private var isSharing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    init(directory: URL,
         emptyMessage: String,
         locationTitle: String,
         locationCaption: String) {
        self.directory = directory
        self.emptyMessage = emptyMessage
        self.locationTitle = locationTitle
        self.locationCaption = locationCaption
        _model = StateObject(wrappedValue: FileListModel(directory: directory))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 中身が 0 件のときこそ「どこを見ればいいのか」が要るので、
            // 一覧の有無にかかわらず常に出す。
            locationBanner
            Divider()

            if model.entries.isEmpty {
                emptyState
            } else {
                selectionBar
                list
            }
        }
        .refreshable { await model.reload() }
        .task { await model.reload() }
        .safeAreaInset(edge: .bottom) {
            if !model.selection.isEmpty {
                HStack(spacing: 12) {
                    Button {
                        isSharing = true
                    } label: {
                        Label("共有 / 書き出し（\(model.selection.count)件）",
                              systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .padding(.vertical, 12)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
        .sheet(isPresented: $isSharing) {
            ShareSheet(items: model.selectedURLs)
        }
        .confirmationDialog("\(model.selection.count)件を削除しますか？",
                            isPresented: $isConfirmingDelete,
                            titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                Task {
                    let failed = await model.deleteSelected()
                    if !failed.isEmpty {
                        errorMessage = "削除できませんでした: " + failed.joined(separator: ", ")
                    }
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("フォルダは中身ごと削除されます。この操作は取り消せません。")
        }
        .alert("エラー",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// このタブが見ているフォルダの実際の場所。
    ///
    /// 「ファイル」アプリ上の表示パスと絶対パスを実行時に解決して出す。
    /// 固定文言 (Documents/Output など) では、コンテナ UUID が再インストールで
    /// 変わることも、LiveContainer 内で公開ルートが変わることも表現できない。
    private var locationBanner: some View {
        LocationDetailView(
            title: locationTitle,
            systemImage: "folder",
            caption: locationCaption,
            url: directory
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // 見出しの代わりに、件数と全選択だけの細い行を置く
    private var selectionBar: some View {
        HStack {
            Text("\(model.selection.count) / \(model.entries.count) 件")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button(model.isAllSelected ? "選択解除" : "すべて選択") {
                model.toggleSelectAll()
            }
            .font(.footnote)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var list: some View {
        List {
            ForEach(model.entries) { entry in
                EntryRow(entry: entry,
                         isSelected: model.selection.contains(entry.url)) {
                    model.toggle(entry.url)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.headline)
            Text("ここに表示されるものはまだありません。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EntryRow: View {
    let entry: StoredEntry
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(entry.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if entry.isDirectory {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
