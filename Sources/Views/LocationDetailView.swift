//
//  LocationDetailView.swift
//  ArcBox
//
//  「どこに出力されたのか」を実行時に解決して表示し、
//  長押しでその場所を「ファイル」アプリで開くビュー。
//
//  固定文言 (例: "Documents/Output に保存しました") では、
//  「ファイル」アプリのどこを開けばいいのかが分からない。
//  コンテナ UUID は再インストールのたびに変わり、
//  LiveContainer 内では公開ルートそのものが変わるため。
//
//  そこで AlarmClock の診断画面と同じく、
//    - 「ファイル」アプリでたどれる表示パス
//    - 実際の絶対パス
//  の 2 つを並べて出す。
//
//  さらに v7 では、長押しの動作を「テキストのコピー」から
//  「そのフォルダを『ファイル』アプリで開く」に変えた。
//  パスを読んで手でたどるより、直接飛べたほうが速いため。
//  (LiveContainer の「データフォルダを開く」と同じ挙動)
//

import SwiftUI
import UIKit

struct LocationDetailView: View {
    let title: String
    let systemImage: String
    /// 補足の 1 行。不要なら nil。
    var caption: String? = nil
    let url: URL

    /// 「ファイル」アプリを開けなかったときの案内。
    /// この場合はパスをクリップボードに入れて、手でたどれるようにする。
    @State private var fallbackMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))

            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // パス部分をまとめて長押しの対象にする。
            // 個別の Text に textSelection(.enabled) を付けると
            // そちらが長押しを奪ってしまうので、v7 では外してある。
            VStack(alignment: .leading, spacing: 6) {
                filesAppPathRow
                actualPathRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onLongPressGesture { openInFilesApp() }

            Label("長押しでこのフォルダを「ファイル」アプリで開きます。",
                  systemImage: "hand.tap")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let fallbackMessage {
                Text(fallbackMessage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - パス表示

    /// 「ファイル」アプリからたどれない場所は、その旨を明示する
    /// (探しても見つからず時間を溶かすのを防ぐため)。
    @ViewBuilder
    private var filesAppPathRow: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("「ファイル」アプリ")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let visible = RuntimeEnvironment.filesAppPath(for: url) {
                Text("このデバイス内 / \(visible)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text("たどれません (Documents の外にあるため)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actualPathRow: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("実際のパス")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(url.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 動作

    /// 「ファイル」アプリでこのフォルダを開く。
    private func openInFilesApp() {
        fallbackMessage = nil

        // 一度も使っていないフォルダは実体が無いことがある。
        // 存在しないパスを渡すと「ファイル」アプリはルートに落ちるため、
        // 先に作っておく。
        try? FileManager.default.createDirectory(at: url,
                                                 withIntermediateDirectories: true)

        guard let target = FileLocations.filesAppURL(for: url) else {
            copyPathAsFallback(reason: "この場所は「ファイル」アプリで開けませんでした。")
            return
        }

        UIApplication.shared.open(target, options: [:]) { success in
            if !success {
                self.copyPathAsFallback(reason: "「ファイル」アプリを開けませんでした。")
            }
        }
    }

    /// 開けなかった場合の保険。パスをクリップボードに入れる。
    private func copyPathAsFallback(reason: String) {
        UIPasteboard.general.string = url.path
        fallbackMessage = reason + "パスをコピーしました。"
    }
}
