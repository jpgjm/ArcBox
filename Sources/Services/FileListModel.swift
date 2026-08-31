import Foundation

/// 一覧に表示する 1 件分
struct StoredEntry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let modifiedAt: Date
    let byteCount: UInt64

    var id: URL { url }
    var name: String { url.lastPathComponent }

    var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        let date = modifiedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(size) ・ \(date)"
    }
}

@MainActor
final class FileListModel: ObservableObject {

    @Published private(set) var entries: [StoredEntry] = []
    @Published private(set) var selection: Set<URL> = []

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    var isAllSelected: Bool {
        !entries.isEmpty && selection.count == entries.count
    }

    /// 一覧の並び順を保ったまま、選択されている URL を返す
    var selectedURLs: [URL] {
        entries.map(\.url).filter { selection.contains($0) }
    }

    func toggle(_ url: URL) {
        if selection.contains(url) {
            selection.remove(url)
        } else {
            selection.insert(url)
        }
    }

    func toggleSelectAll() {
        if isAllSelected {
            selection.removeAll()
        } else {
            selection = Set(entries.map(\.url))
        }
    }

    /// 選択中の項目を削除する。フォルダは中身ごと消える。
    /// - Returns: 削除に失敗したファイル名（すべて成功なら空）
    @discardableResult
    func deleteSelected() async -> [String] {
        let targets = selectedURLs
        guard !targets.isEmpty else { return [] }

        let failed = await Task.detached(priority: .userInitiated) { () -> [String] in
            var failures: [String] = []
            for url in targets {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    failures.append(url.lastPathComponent)
                }
            }
            return failures
        }.value

        selection.removeAll()
        await reload()
        return failed
    }

    func reload() async {
        let target = directory
        let loaded = await Task.detached(priority: .userInitiated) {
            FileListModel.load(from: target)
        }.value

        entries = loaded
        // 消えたファイルの選択状態は捨てる
        let available = Set(loaded.map(\.url))
        selection = selection.intersection(available)
    }

    /// バックグラウンドから呼ぶので MainActor 隔離を外す。
    /// （FileListModel が @MainActor なので、これを付けないと
    ///   Task.detached から呼べずコンパイルエラーになる）
    nonisolated private static func load(from directory: URL) -> [StoredEntry] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey,
                                                           .contentModificationDateKey])
            return StoredEntry(url: url,
                               isDirectory: values?.isDirectory ?? false,
                               modifiedAt: values?.contentModificationDate ?? .distantPast,
                               byteCount: FileLocations.byteCount(at: url))
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }   // 新しい順
    }
}
