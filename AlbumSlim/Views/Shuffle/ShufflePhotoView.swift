import SwiftUI
import Photos

/// 静态图页面：aspectFill 全屏；非 active 时释放像素数据
struct ShufflePhotoView: View {
    @Environment(AppServiceContainer.self) private var services
    let item: ShuffleItem
    let isActive: Bool

    @State private var image: UIImage?
    @State private var downloadProgress: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    ProgressView(value: downloadProgress == 0 ? nil : downloadProgress)
                        .tint(.white)
                        .controlSize(.large)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: isActive) {
            if isActive {
                await load()
                await services.backdrop.sample(image: image)
            } else {
                image = nil
                downloadProgress = 0
            }
        }
    }

    private func load() async {
        guard image == nil else { return }
        let scale = UIScreen.main.scale
        let bounds = UIScreen.main.bounds.size
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        image = await services.photoLibrary.loadFullImage(for: item.asset, size: size) { progress in
            downloadProgress = progress
        }
    }
}
