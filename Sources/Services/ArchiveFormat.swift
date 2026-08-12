import Foundation
import UniformTypeIdentifiers
import PLzmaSDK

/// 対応するアーカイブ形式
enum ArchiveFormat: String, CaseIterable, Identifiable {
    case sevenZ
    case tar

    var id: String { rawValue }

    /// 拡張子（ドットなし）
    var fileExtension: String {
        switch self {
        case .sevenZ: return "7z"
        case .tar:    return "tar"
        }
    }

    /// UI 表示用（ドットあり）
    var displayName: String { "." + fileExtension }

    /// PLzmaSDK に渡す型
    var plzmaType: FileType {
        switch self {
        case .sevenZ: return .sevenZ
        case .tar:    return .tar
        }
    }

    /// 圧縮レベルの概念があるか。tar は単に束ねるだけなので無い。
    var supportsCompressionLevel: Bool { self == .sevenZ }

    var contentType: UTType {
        switch self {
        case .sevenZ: return UTType(filenameExtension: "7z") ?? .data
        case .tar:    return UTType("public.tar-archive") ?? UTType(filenameExtension: "tar") ?? .data
        }
    }

    /// 拡張子から形式を判定する
    static func detect(from url: URL) -> ArchiveFormat? {
        let ext = url.pathExtension.lowercased()
        return ArchiveFormat.allCases.first { $0.fileExtension == ext }
    }

    static var allContentTypes: [UTType] { allCases.map(\.contentType) }
}
