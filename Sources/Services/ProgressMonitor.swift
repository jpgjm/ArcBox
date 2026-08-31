import Foundation
import PLzmaSDK

/// PLzmaSDK の進捗コールバックを受け取って UI に流す中継役。
///
/// - `EncoderDelegate` / `DecoderDelegate` はどちらも
///   `(対象, path: String, progress: Double)` を返すだけなので 1 クラスで両対応する。
/// - コールバックは圧縮 / 展開を実行しているバックグラウンドスレッドから来る。
/// - 呼び出し頻度が高いので `minimumInterval` で間引く（progress = 1.0 は必ず通す）。
final class ArchiveProgressReporter: EncoderDelegate, DecoderDelegate {

    private let handler: (String, Double) -> Void
    private let minimumInterval: TimeInterval
    private let lock = NSLock()
    private var lastReport: TimeInterval = 0

    init(minimumInterval: TimeInterval = 0.1,
         handler: @escaping (String, Double) -> Void) {
        self.minimumInterval = minimumInterval
        self.handler = handler
    }

    func encoder(encoder: Encoder, path: String, progress: Double) {
        report(path: path, progress: progress)
    }

    func decoder(decoder: Decoder, path: String, progress: Double) {
        report(path: path, progress: progress)
    }

    private func report(path: String, progress: Double) {
        lock.lock()
        let now = Date.timeIntervalSinceReferenceDate
        let shouldReport = progress >= 1.0 || (now - lastReport) >= minimumInterval
        if shouldReport { lastReport = now }
        lock.unlock()

        guard shouldReport else { return }
        handler(path, progress)
    }
}

/// 画面に出す進捗の状態
@MainActor
final class ProgressMonitor: ObservableObject {

    /// 0.0...1.0
    @Published private(set) var fraction: Double = 0

    /// 現在処理中のアーカイブ内パス
    @Published private(set) var currentPath: String = ""

    /// バックグラウンドスレッドから安全に呼べる更新用ハンドラを作る
    nonisolated func makeHandler() -> (String, Double) -> Void {
        { [weak self] path, progress in
            Task { @MainActor in
                self?.update(path: path, progress: progress)
            }
        }
    }

    func update(path: String, progress: Double) {
        fraction = min(max(progress, 0), 1)
        currentPath = path
    }

    func reset() {
        fraction = 0
        currentPath = ""
    }

    var displayName: String {
        currentPath.isEmpty ? "" : (currentPath as NSString).lastPathComponent
    }
}
