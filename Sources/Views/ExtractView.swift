import SwiftUI
import UniformTypeIdentifiers

struct ExtractView: View {
    @StateObject private var monitor = ProgressMonitor()

    @State private var archive: URL?
    @State private var isImporting = false
    @State private var isWorking = false
    @State private var destination: URL?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("アーカイブ") {
                Button {
                    isImporting = true
                } label: {
                    Label("アーカイブを選択", systemImage: "doc.badge.plus")
                }
                Text(archive?.lastPathComponent ?? "未選択")
                    .foregroundStyle(archive == nil ? .secondary : .primary)
                    .lineLimit(1)
                Text("対応形式: .7z / .tar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task { await runExtract() }
                } label: {
                    Text("展開")
                }
                .disabled(archive == nil || isWorking)

                if isWorking {
                    ProgressRow(title: "展開中", monitor: monitor)
                }
            }

            if let destination {
                Section("結果") {
                    Text(destination.lastPathComponent)
                    Text("Documents/Extracted に展開しました。Extracted タブから共有できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: ArchiveFormat.allContentTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                archive = urls.first
                destination = nil
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("エラー",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func runExtract() async {
        guard let archive else { return }
        isWorking = true
        destination = nil
        monitor.reset()

        let baseName = archive.deletingPathExtension().lastPathComponent
        let outDir = FileLocations.uniqueDirectory(in: FileLocations.extracted,
                                                   baseName: baseName)
        let handler = monitor.makeHandler()

        do {
            try await Task.detached(priority: .userInitiated) {
                try ArchiveService.extract(archive: archive,
                                           to: outDir,
                                           progress: handler)
            }.value
            destination = outDir
        } catch {
            try? FileManager.default.removeItem(at: outDir)
            errorMessage = error.localizedDescription
        }

        monitor.reset()
        isWorking = false
    }
}
