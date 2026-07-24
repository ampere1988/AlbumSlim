import SwiftUI

struct ShareCardContent: View {
    let freedSpace: Int64
    let totalFreed: Int64
    let cleanupCount: Int
    /// 累计模式：用于"成就总览"等无"本次清理"上下文的场景。
    /// 主标题文案改为"累计释放"，并隐藏下方与主标题重复的累计释放小字统计。
    var isCumulative: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.orange, .red, .pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 50))
                    .foregroundStyle(.white.opacity(0.9))

                Text("闪图")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                VStack(spacing: 8) {
                    Text(isCumulative ? String(localized: "累计释放") : String(localized: "本次释放"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(freedSpace.formattedFileSize)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Divider()
                    .background(.white.opacity(0.3))
                    .padding(.horizontal, 40)

                HStack(spacing: 32) {
                    if !isCumulative {
                        VStack(spacing: 4) {
                            Text(totalFreed.formattedFileSize)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("累计释放")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    VStack(spacing: 4) {
                        Text("\(cleanupCount)")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("清理次数")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()

                Text("AlbumSlim - 智能相册管理")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 16)
            }
        }
    }
}
