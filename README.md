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
Sources/Views/FileListView.swift        保存済みファイルの一覧・複数選択・共有・削除
Sources/Services/ArchiveService.swift   PLzmaSDK ラッパー（圧縮・展開）
Sources/Services/FileLocations.swift    出力先パス・共有シート・サイズ計算
Sources/Services/FileListModel.swift    一覧の読み込み・選択状態・一括削除
Sources/Services/ProgressMonitor.swift  進捗の中継（EncoderDelegate / DecoderDelegate）
.github/workflows/build.yml     未署名 ipa をビルドして artifact に上げる
```

## 使い方

1. リポジトリに push すると Actions が走り、`ArcBox-ipa` という artifact ができる
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

Actions が失敗すると、`build-failure` という artifact に `build-failure.zip` が上がる。
中身は次の通り（Mac が無くても iPad だけで原因を追えるようにしてある）:

```
failure-bundle/
├── logs/
│   ├── xcodebuild.log      ビルド全文ログ
│   ├── errors.txt          error 行だけ抜き出したもの ← まずこれ
│   ├── warnings.txt        warning 行だけ
│   ├── xcodegen.log        プロジェクト生成ログ
│   ├── toolchain.log       Xcode / Swift / SDK のバージョン
│   └── *.xcactivitylog     Xcode のビルドログ本体
├── project/                失敗時点の Sources / Resources / project.yml / Package.resolved
└── environment.txt         ランナー環境・SPM の展開状況・生成物の有無
```

Actions の実行結果ページ上部の Summary にも error 行が最大 60 行まで表示されるので、
軽い失敗ならダウンロードせずそこで判る。

なお、失敗を握りつぶさないよう `continue-on-error` は使わず、
`if: failure()` の後続ステップとして収集している（ジョブは失敗のまま終わる）。

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
