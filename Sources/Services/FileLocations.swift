import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum FileLocations {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 圧縮結果の出力先（Documents/Output）
    static var output: URL {
        let url = documents.appendingPathComponent("Output", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 展開結果の出力先（Documents/Extracted）
    static var extracted: URL {
        let url = documents.appendingPathComponent("Extracted", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 同名ファイルがある場合に "name-2.7z" のように退避した URL を返す
    static func uniqueURL(in directory: URL, baseName: String, extension ext: String) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(index).\(ext)")
            index += 1
        }
        return candidate
    }

    /// 重複しないディレクトリ名を返す
    static func uniqueDirectory(in directory: URL, baseName: String) -> URL {
        var candidate = directory.appendingPathComponent(baseName, isDirectory: true)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }

    static let sevenZType: UTType = UTType(filenameExtension: "7z") ?? .data

    // MARK: - 「ファイル」アプリで開く

    /// 「ファイル」アプリを指定フォルダで開くための URL を組み立てる。
    ///
    /// LiveContainer の「データフォルダを開く」と同じ仕組み。
    /// (LiveContainerSwiftUI/Views/AppList/LCAppBanner/LCAppBannerViewController.swift)
    ///
    /// ```swift
    /// let url = URL(string: "shareddocuments://\(LCPath.dataPath.path)/\(folderName)")
    /// UIApplication.shared.open(url)
    /// ```
    ///
    /// 渡すのは表示用の相対パスではなく **実際の絶対パス**。
    /// `UIFileSharingEnabled` で公開されている領域の中であれば、
    /// 「ファイル」アプリがその階層まで開いてくれる。
    ///
    /// LiveContainer 内で動いている場合、自分の Documents の実体は
    /// ホストの Documents 配下 (`.../Documents/Data/Application/{ゲストUUID}/Documents/...`)
    /// にあり、これはホストの `UIFileSharingEnabled` で公開されているため
    /// そのまま到達できる。
    ///
    /// - Note: LiveContainer 本家は素の `URL(string:)` を使っているが、
    ///   パスに空白などが含まれると `nil` になって無言で失敗する。
    ///   ここではパーセントエンコードしてから組み立てる。
    static func filesAppURL(for directory: URL) -> URL? {
        let path = directory.path
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "shareddocuments://" + encoded)
    }

    /// ファイルならそのサイズ、フォルダなら配下の合計サイズ。存在しなければ 0。
    static func byteCount(at url: URL) -> UInt64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }

        if isDirectory.boolValue {
            var total: UInt64 = 0
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return 0 }

            for case let child as URL in enumerator {
                let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true {
                    total += UInt64(values?.fileSize ?? 0)
                }
            }
            return total
        } else {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return UInt64(values?.fileSize ?? 0)
        }
    }
}

/// 生成した .7z を他アプリ／ファイルアプリに渡すための共有シート
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
