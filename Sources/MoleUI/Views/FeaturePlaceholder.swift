import SwiftUI

/// 通用占位页：展示功能图标、名称与简介。
struct FeaturePlaceholder: View {
    let section: AppSection

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: section.symbol)
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text(section.title)
                .font(.title2.weight(.semibold))
            Text(section.placeholderDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(section.title)
    }
}
