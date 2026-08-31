import SwiftUI
import UniformTypeIdentifiers

struct CompressView: View {
    @StateObject private var monitor = ProgressMonitor()

    @State private var sources: [URL] = []
    @State private var archiveName: String = "archive"
    @State private var format: ArchiveFormat = .sevenZ
    @State private var level: Double = 0          // 既定は 0 = 無圧縮(ストア)
    @State private var isImporting = false
    @State private var isWorking = false
    @State private var resultURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("対象") {
                Button {
                    isImporting = true
                } label: {
                    Label("ファイル / フォルダを選択", systemImage: "plus")
                }

                if sources.isEmpty {
                    Text("未選択").foregroundStyle(.secondary)
                } else {
                    ForEach(sources, id: \.self) { url in
                        Text(url.lastPathComponent).lineLimit(1)
                    }
                    .onDelete { sources.remove(atOffsets: $0) }
                }
            }

            Section("出力") {
                HStack {
                    TextField("ファイル名", text: $archiveName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    // 拡張子をタップして形式を切り替える
                    Menu {
                        ForEach(ArchiveFormat.allCases) { candidate in
                            Button {
                                format = candidate
                            } label: {
                                if candidate == format {
                                    Label(candidate.displayName, systemImage: "checkmark")
                                } else {
                                    Text(candidate.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(format.displayName)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                    }
                }

                if format.supportsCompressionLevel {
                    VStack(alignment: .leading) {
                        Text("圧縮レベル: \(Int(level))\(level == 0 ? "（無圧縮 / ストア）" : "")")
                        Slider(value: $level, in: 0...9, step: 1)
                    }
                    Text("中身が既に zip などで圧縮済みの場合は 0 が最速で、サイズもほぼ変わりません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("tar は圧縮せずにまとめるだけの形式です。圧縮レベルはありません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await runCompress() }
                } label: {
                    Text("\(format.displayName) を作成")
                }
                .disabled(sources.isEmpty || archiveName.isEmpty || isWorking)

                if isWorking {
                    ProgressRow(title: "圧縮中", monitor: monitor)
                }
            }

            if let resultURL {
                Section {
                    Text(resultURL.lastPathComponent)

                    // パスは固定文言にしない。コンテナ UUID は再インストールで
                    // 変わり、LiveContainer 内では公開ルート自体が変わるため、
                    // 実行時に解決したものを出す。
                    LocationDetailView(
                        title: "保存先フォルダ",
                        systemImage: "folder",
                        caption: "Output タブから共有 / 書き出しできます。",
                        url: resultURL.deletingLastPathComponent()
                    )
                } header: {
                    Text("結果")
                }
            }
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [.item, .folder],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls where !sources.contains(url) { sources.append(url) }
                if let first = urls.first, sources.count == urls.count {
                    archiveName = first.deletingPathExtension().lastPathComponent
                }
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

    private func runCompress() async {
        isWorking = true
        resultURL = nil
        monitor.reset()

        let destination = FileLocations.uniqueURL(in: FileLocations.output,
                                                  baseName: archiveName,
                                                  extension: format.fileExtension)
        let inputs = sources
        let selectedFormat = format
        let compressionLevel = UInt8(level)
        let handler = monitor.makeHandler()

        do {
            try await Task.detached(priority: .userInitiated) {
                try ArchiveService.compress(sources: inputs,
                                            to: destination,
                                            format: selectedFormat,
                                            level: compressionLevel,
                                            progress: handler)
            }.value
            resultURL = destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            errorMessage = error.localizedDescription
        }

        monitor.reset()
        isWorking = false
    }
}

/// 圧縮・展開で共通の進捗行
struct ProgressRow: View {
    let title: String
    @ObservedObject var monitor: ProgressMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: monitor.fraction)

            HStack {
                Text("\(title)… \(Int(monitor.fraction * 100))%")
                Spacer()
                if !monitor.displayName.isEmpty {
                    Text(monitor.displayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
