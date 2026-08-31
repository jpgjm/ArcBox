# ArcBox

iOS 用のアーカイブ圧縮 / 展開アプリ（**.7z / .tar** 対応、個人利用・SideStore 配布前提、ストア公開なし）。

- 圧縮エンジン: [PLzmaSDK](https://github.com/OlehKulykov/PLzmaSDK) 1.6.1（Swift Package Manager）
- ライセンス: PLzmaSDK の Swift 部分は MIT、LZMA SDK 本体はパブリックドメイン
- 最低 iOS: 16.0
- UI: SwiftUI（圧縮タブ / 展開タブ）

## 構成

```
project.yml                     XcodeGen 定義（SPM 依存もここ）
Resources/Info.plist            Files 連携 + 7z / tar の UTI 宣言
Sources/App/ArcBoxApp.swift
Sources/Views/RootView.swift            タブ構成（圧縮 / 展開 / Output / Extracted）
Sources/Services/ArchiveFormat.swift    対応形式（.7z / .tar）の定義
Sources/Views/CompressView.swift
Sources/Views/ExtractView.swift
Sources/Views/FileListView.swift        保存済みファイルの一覧・複数選択・共有・削除 + 保存場所の表示
Sources/Services/ArchiveService.swift   PLzmaSDK ラッパー（圧縮・展開）
Sources/Services/FileLocations.swift    出力先パス・共有シート・サイズ計算
Sources/Services/FileListModel.swift    一覧の読み込み・選択状態・一括削除
Sources/Services/ProgressMonitor.swift  進捗の中継（EncoderDelegate / DecoderDelegate）
Sources/Services/RuntimeEnvironment.swift  実行環境の判定・「ファイル」アプリ上の表示パス解決
Sources/Views/LocationDetailView.swift     出力先パスの表示（表示パス + 実際のパス）
.github/workflows/build-ipa.yml 未署名 ipa をビルドして artifact に上げる（汎用 rev7）
```

## 使い方

1. リポジトリに push すると Actions が走り、`<ビルド時刻>_<リポジトリ名>_ipa` という artifact ができる
2. ダウンロードして SideStore でインストール
3. 圧縮結果は `Documents/Output/`、展開結果は `Documents/Extracted/` に出る
   （`UIFileSharingEnabled` を入れてあるので「ファイル」アプリ → このアプリ、で直接見える）
4. 共有 / 書き出しは **Output タブ / Extracted タブ**から行う。
   チェックを付けて複数まとめて共有できる（v4 で圧縮・展開画面の共有ボタンは廃止）。
   同じ画面から選択中のものをまとめて削除もできる（確認ダイアログあり / フォルダは中身ごと削除）

## 実装上の要点

### archivePath を必ず指定している

`encoder.add(path:)` を単独で呼ぶと、渡したパスが**そのまま**アーカイブ内のパスになる。
iOS ではファイルピッカーが返す URL が `/private/var/mobile/Containers/...` という
絶対パスなので、指定しないとその階層ごと 7z に埋まってしまう。
そのため `archivePath: Path(source.lastPathComponent)` を必ず渡している。

### security scope を compress() まで保持している

`add(path:)` は登録するだけで、実際にファイルを読むのは `compress()` の中。
ループ内で `stopAccessingSecurityScopedResource()` すると読み取り時に権限切れになるため、
`ArchiveService.compress` では全 URL のスコープを最後まで開いたままにしている。

### 圧縮レベル 0

既定を 0（ストア）にしてある。中身が既に zip / 7z で圧縮済みのファイル群では、
LZMA2 をかけてもサイズはほぼ縮まず時間だけ食うため。

## 進捗表示について（v3）

CI の `Inspect PLzmaSDK API` ステップでデリゲートのシグネチャが確定したため、
v2 のポーリング方式をやめて公式の delegate 方式に切り替えた。

```swift
public protocol EncoderDelegate: AnyObject {
    func encoder(encoder: Encoder, path: String, progress: Double)
}
public protocol DecoderDelegate: AnyObject {
    func decoder(decoder: Decoder, path: String, progress: Double)
}
```

`ArchiveProgressReporter` が両方を実装し、圧縮も展開も同じ経路で
「% + 現在処理中のファイル名」を出す。圧縮レベルに関係なく正確な % が出る。

実装上の注意:

- delegate は `AnyObject`（weak 保持の可能性がある）ため、
  `withExtendedLifetime(reporter)` で `compress()` / `extract()` の完了まで寿命を確保している。
- コールバックはバックグラウンドスレッドから高頻度で来るので、
  `minimumInterval`（既定 0.1 秒）で間引いてから MainActor に渡している。
  `progress = 1.0` だけは間引かず必ず通す。

## 出力先の表示について（v5 / v6 / v7）

圧縮の「結果」セクションは、以前は `Documents/Output に保存しました。` という
固定文言だった。これだと「ファイル」アプリのどこを開けばいいのか判らない。

- アプリのコンテナ UUID は再インストールのたびに変わる
- LiveContainer 内で動かすと、公開されるルートがホスト（LiveContainer）側になり、
  ゲストのコンテナは `LiveContainer/Data/Application/{ゲストUUID}/Documents/...` に潜る

そこで AlarmClock の診断画面と同じ方式に変えた。`RuntimeEnvironment` が
実行時にパスを解決し、`LocationDetailView` が 2 段で表示する。

```
「ファイル」アプリ
このデバイス内 / ArcBox/Output
実際のパス
/var/mobile/Containers/Data/Application/{UUID}/Documents/Output
```

判定は `LC_HOME_PATH` 環境変数の有無で行う。LiveContainer は HOME を
差し替える前に本来の HOME をこの変数へ退避しているため、
これがあれば LC のゲスト、無ければ通常インストールと判断できる。

`Documents` の外にあるパスを渡した場合は「たどれません」と明示する。
「ファイル」アプリに公開されるのは `UIFileSharingEnabled` が有効なアプリの
`Documents` だけなので、探しても見つからず時間を溶かすのを防ぐため。

v6 で表示箇所を 4 つに揃えた。

| 場所 | 表示するフォルダ |
|---|---|
| 圧縮タブ / 結果 | `Documents/Output` |
| 展開タブ / 結果 | `Documents/Extracted` |
| Output タブ | `Documents/Output` |
| Extracted タブ | `Documents/Extracted` |

タブ側は一覧が 0 件でも出す。中身が無いときこそ「どこに置けば / どこを見れば
いいのか」が必要になるため。

### 長押しで「ファイル」アプリを開く（v7）

v6 まではパス部分に `textSelection(.enabled)` を付けて長押しコピーにしていたが、
コピーしたところで「ファイル」アプリには貼り付け先が無く、結局手でたどることに
なっていた。v7 では長押しの動作を「そのフォルダを『ファイル』アプリで開く」に変えた。

LiveContainer の「データフォルダを開く」と同じ仕組みで、`shareddocuments://` に
**実際の絶対パス**をつなげて `UIApplication.shared.open` に渡す。

```swift
// LiveContainer 本家 (LCAppBannerViewController.swift)
let url = URL(string: "shareddocuments://\(LCPath.dataPath.path)/\(folderName)")
UIApplication.shared.open(url)
```

ArcBox 側は `FileLocations.filesAppURL(for:)` がこの URL を組み立てる。
本家と違う点は 1 つだけで、パスをパーセントエンコードしてから渡している
（本家は素の `URL(string:)` なので、パスに空白が混ざると `nil` になって無言で失敗する）。

開けなかった場合は保険としてパスをクリップボードに入れ、その旨を画面に出す。
`textSelection` は長押しを奪ってしまうので外した。

## 圧縮したアーカイブの更新日時（v7 で修正）

PLzmaSDK が書き終えた直後のアーカイブは、更新日時が
`1970-01-01 00:00 UTC`（epoch 0）のままになっていた。
一覧は更新日時の新しい順に並べているため、Output タブに複数のアーカイブが
溜まると並び順が機能しなくなる。

`ArchiveService.compress` の最後で明示的に現在時刻を入れて対処している。

```swift
try? FileManager.default.setAttributes(
    [.modificationDate: Date(), .creationDate: Date()],
    ofItemAtPath: destination.path
)
```

展開側はフォルダを OS が作るのでこの問題は起きない。圧縮側だけの後始末。

## 既知の制限・次にやるなら

- **展開前の中身一覧なし**: `decoder.count()` / `decoder.item(at:)` で実装可能。
- **NFC 正規化は未適用**: `ArchiveService.compress` にコメントで入れ口だけ用意してある。
  ただしフォルダを丸ごと追加した場合、中のエントリ名は PLzmaSDK が
  ファイルシステムから読むため、この一行では NFD のまま残る。全エントリを NFC に
  揃えたい場合はフォルダを自前で再帰列挙して `add(stream:archivePath:)` で1件ずつ
  追加する形に変える必要がある。
- **共有シート拡張なし**: 「ファイル」アプリの操作メニューから直接呼びたい場合は
  Share/Action Extension が必要。ただし拡張は別 bundle ID になるため、
  無料 Apple ID の App ID 枠（7日で10個）を追加で消費する。

## 動かなかったときに最初に見るところ

### ビルドが失敗した場合

ワークフローは成功でも失敗でも次の 3 つを上げる（Mac が無くても iPad だけで原因を追える）。
どれも頭に「JST のビルド時刻 + リポジトリ名」が付く。

```
<stamp>_<repo>_xcodebuild-log   ビルド全文ログ ← まずこれ
<stamp>_<repo>_Repository       ビルド前のリポジトリのスナップショット
<stamp>_<repo>_ipa              成功時のみ
```

ログとスナップショットは `if: always()` なので、ビルドが落ちても残る。
失敗を握りつぶさないよう `continue-on-error` は使っていない（ジョブは失敗のまま終わる）。

### 過去に踏んだビルドエラー

- `main actor-isolated static method 'load(from:)' cannot be called from outside of the actor`
  → `@MainActor` を付けた型の中のメソッドは、たとえ `static` でも MainActor 隔離になる。
  `Task.detached` の中から呼ぶものには `nonisolated` を付ける。
- `ContentUnavailableView` / `ToolbarItem(placement: .topBarTrailing)` は **iOS 17+**。
  このプロジェクトの `deploymentTarget` は 16.0 なので使えない。

### その他

- `xcodebuild` が SPM 解決で落ちる → PLzmaSDK は `swift-tools-version: 6.1` なので
  Xcode 16.3 以上が必要。`setup-xcode` の `latest-stable` で足りているか Actions のログで確認。
- `.app` はできるのに起動しない → `Verify .app` ステップで実行バイナリの有無を見ている。
  それが通っているなら署名側（SideStore）の問題。
