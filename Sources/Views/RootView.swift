import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            CompressView()
                .tabItem { Label("圧縮", systemImage: "archivebox") }

            ExtractView()
                .tabItem { Label("展開", systemImage: "shippingbox") }

            FileListView(directory: FileLocations.output,
                         emptyMessage: "作成したアーカイブはまだありません")
                .tabItem { Label("Output", systemImage: "doc.zipper") }

            FileListView(directory: FileLocations.extracted,
                         emptyMessage: "展開したフォルダはまだありません")
                .tabItem { Label("Extracted", systemImage: "folder") }
        }
    }
}
