import SwiftUI
import UIKit

extension View {
    /// iPad 上限制内容最大宽度并居中，iPhone 不变。用于避免横屏下表单/列表被过度拉伸。
    @ViewBuilder
    func iPadContentMaxWidth(_ maxWidth: CGFloat = 700) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            self
        }
    }
}
