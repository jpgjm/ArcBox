//
//  RuntimeEnvironment.swift
//  ArcBox
//
//  「このアプリが今どこで動いているか」を判定し、
//  出力先パスを画面に出すための表示用文字列を組み立てる。
//
//  背景:
//    出力先を「Documents/Output」と固定文言で書いてしまうと、
//    実際に「ファイル」アプリのどこを開けばよいのかが分からない。
//    アプリのコンテナ UUID は再インストールのたびに変わるうえ、
//    LiveContainer (以下 LC) 内で動かした場合は
//    そもそも公開されているルートがホスト側になる。
//
//    そのため、パスは固定文字列ではなく実行時に解決して表示する。
//    (AlarmClock の RuntimeEnvironment と同じ方針・同じ判定方法)
//
//  LC の判定方法:
//    LC は HOME を差し替える *前に*、本来の HOME を環境変数に退避している。
//
//      // LiveContainer/LCBootstrap.m
//      setenv("LC_HOME_PATH", getenv("HOME"), 0);
//
//    したがって `LC_HOME_PATH` の有無がそのまま「LC 内かどうか」の判定になる。
//    通常のインストールではこの環境変数は存在しない。
//

import Foundation

/// 実行環境の判定と、環境依存のパス表示。
enum RuntimeEnvironment {

    /// LiveContainer が退避しているホスト本来の HOME を指す環境変数名。
    private static let lcHomePathKey = "LC_HOME_PATH"

    /// LiveContainer のゲストとして動いているか。
    ///
    /// 一度決まれば変わらないので評価結果を保持する。
    static let isLiveContainer: Bool = {
        ProcessInfo.processInfo.environment[lcHomePathKey] != nil
    }()

    /// LiveContainer 本体 (ホスト) の実コンテナのパス。
    /// 通常インストール時は nil。
    static let hostHomePath: String? = {
        ProcessInfo.processInfo.environment[lcHomePathKey]
    }()

    /// 診断表示やログに出す 1 行の要約。
    static var summary: String {
        isLiveContainer ? "LiveContainer (ゲスト)" : "通常インストール"
    }

    // MARK: - ファイルアプリ上の表示パス

    /// 「ファイル」アプリ上で、このアプリの Documents が見えている名前。
    ///
    /// 通常インストールなら自分の表示名。LC 内ではホストの Documents が
    /// 公開されるので "LiveContainer" になる。
    static var filesAppRootName: String {
        if isLiveContainer { return "LiveContainer" }
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? "ArcBox"
    }

    /// 「ファイル」アプリでたどれる表示パスに変換する。たどれない場所なら nil。
    ///
    /// iOS が「ファイル」アプリに公開するのは、`UIFileSharingEnabled` が有効な
    /// アプリの **Documents フォルダだけ**。それ以外は公開されない。
    ///
    /// LiveContainer 内では、公開されるのは **ホスト (LiveContainer) の Documents** で、
    /// ゲストのコンテナはその配下の `Data/Application/{ゲスト UUID}/` に置かれている。
    ///
    /// ```
    /// ファイル > このデバイス内 > LiveContainer
    ///   └ Data/Application/{ゲストUUID}/Documents/Output/
    /// ```
    static func filesAppPath(for url: URL) -> String? {
        // ファイルアプリに公開されている実フォルダ。
        let exposedDocuments: String
        if let hostHome = hostHomePath {
            exposedDocuments = hostHome + "/Documents"
        } else {
            exposedDocuments = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0].path
        }

        let target = normalized(url.path)
        let root = normalized(exposedDocuments)

        guard target == root || target.hasPrefix(root + "/") else {
            return nil
        }
        let relative = String(target.dropFirst(root.count))
        return filesAppRootName + relative
    }

    /// `/private/var/...` と `/var/...` を同一視するためにパスを正規化する。
    /// (`/var` は `/private/var` へのシンボリックリンクなので、
    ///  どちらの表記で来ても比較できるようにしておく)
    private static func normalized(_ path: String) -> String {
        var p = path
        if p.hasPrefix("/private/var/") {
            p.removeFirst("/private".count)
        }
        while p.count > 1 && p.hasSuffix("/") {
            p.removeLast()
        }
        return p
    }
}
