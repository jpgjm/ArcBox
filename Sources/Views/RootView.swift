import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            CompressView()
                .tabItem { Label("圧縮", systemImage: "archivebox") }

            ExtractView()
                .tabItem { Label("展開", systemImage: "shippingbox") }

            FileListView(directory: FileLocations.output,
                         emptyMessage: "作成したアーカイブはまだありません",
                         locationTitle: "保存先フォルダ",
                         locationCaption: "圧縮で作成したアーカイブはここに出力されます。")
                .tabItem { Label("Output", systemImage: "doc.zipper") }

            FileListView(directory: FileLocations.extracted,
                         emptyMessage: "展開したフォルダはまだありません",
                         locationTitle: "展開先フォルダ",
                         locationCaption: "展開した中身はここに出力されます。")
                .tabItem { Label("Extracted", systemImage: "folder") }
        }
    }
}
