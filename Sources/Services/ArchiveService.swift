import Foundation
import PLzmaSDK

enum ArchiveError: LocalizedError {
    case openFailed
    case operationFailed
    case noSourceSelected
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .openFailed:       return "アーカイブを開けませんでした。"
        case .operationFailed:  return "処理に失敗しました。"
        case .noSourceSelected: return "対象が選択されていません。"
        case .unsupportedFormat(let ext):
            return "対応していない形式です（.\(ext)）。"
        }
    }
}

enum ArchiveService {

    // MARK: - 圧縮

    /// - Parameters:
    ///   - sources: 圧縮対象（ファイル / フォルダ）。security-scoped URL を想定。
    ///   - destination: 出力先のアーカイブパス
    ///   - format: .sevenZ または .tar
    ///   - level: 0 = 無圧縮(ストア) ... 9 = 最大圧縮（tar では無視される）
    ///   - progress: (アーカイブ内パス, 0.0...1.0)。バックグラウンドスレッドから呼ばれる。
    static func compress(sources: [URL],
                         to destination: URL,
                         format: ArchiveFormat,
                         level: UInt8,
                         progress: ((String, Double) -> Void)? = nil) throws {
        guard !sources.isEmpty else { throw ArchiveError.noSourceSelected }

        // security scope は compress() が実際に読み込むまで開けておく必要がある
        var scopedURLs: [URL] = []
        defer { scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }

        let reporter = progress.map { ArchiveProgressReporter(handler: $0) }

        let outStream = try OutStream(path: try Path(destination.path))
        let encoder = try Encoder(stream: outStream,
                                  fileType: format.plzmaType,
                                  method: .LZMA2,
                                  delegate: reporter)
        // tar には圧縮レベルの概念が無いので設定しない
        if format.supportsCompressionLevel {
            try encoder.setCompressionLevel(level)
        }

        for source in sources {
            if source.startAccessingSecurityScopedResource() {
                scopedURLs.append(source)
            }
            // archivePath を必ず指定する。省略するとサンドボックスの絶対パス
            // (/private/var/mobile/...) がそのままアーカイブ内に埋め込まれる。
            let entryName = source.lastPathComponent
            // NFC 正規化したい場合はここで:
            // let entryName = source.lastPathComponent.precomposedStringWithCanonicalMapping
            try encoder.add(path: try Path(source.path),
                            mode: .default,
                            archivePath: try Path(entryName))
        }

        // delegate は AnyObject（weak 保持の可能性あり）なので、
        // compress() が終わるまで reporter が解放されないよう明示的に寿命を延ばす。
        try withExtendedLifetime(reporter) {
            guard try encoder.open() else { throw ArchiveError.openFailed }
            guard try encoder.compress() else { throw ArchiveError.operationFailed }
        }
    }

    // MARK: - 展開

    /// - Parameters:
    ///   - archive: 展開するアーカイブ
    ///   - directory: 展開先ディレクトリ（無ければ作成）
    ///   - progress: (アーカイブ内パス, 0.0...1.0)。バックグラウンドスレッドから呼ばれる。
    ///
    /// 形式は拡張子から判定する。
    static func extract(archive: URL,
                        to directory: URL,
                        progress: ((String, Double) -> Void)? = nil) throws {
        guard let format = ArchiveFormat.detect(from: archive) else {
            throw ArchiveError.unsupportedFormat(archive.pathExtension)
        }

        let scoped = archive.startAccessingSecurityScopedResource()
        defer { if scoped { archive.stopAccessingSecurityScopedResource() } }

        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)

        let reporter = progress.map { ArchiveProgressReporter(handler: $0) }

        let inStream = try InStream(path: try Path(archive.path))
        let decoder = try Decoder(stream: inStream,
                                  fileType: format.plzmaType,
                                  delegate: reporter)

        try withExtendedLifetime(reporter) {
            guard try decoder.open() else { throw ArchiveError.openFailed }
            guard try decoder.extract(to: try Path(directory.path)) else {
                throw ArchiveError.operationFailed
            }
        }
    }
}
