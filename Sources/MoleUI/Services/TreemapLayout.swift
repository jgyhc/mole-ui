import Foundation

/// 方形树图（Squarified Treemap）布局算法（Bruls, Huizing, van Wijk, 2000）。
/// 纯函数，便于单元测试。
enum TreemapLayout {
    struct Rect {
        var x: Double
        var y: Double
        var w: Double
        var h: Double

        var area: Double { w * h }
    }

    /// 将 sizes 布局进 rect，返回与输入同序的矩形数组。
    /// 要求 sizes 已按降序排列；size <= 0 的项不占空间（返回空矩形）。
    static func layout(sizes: [Double], in rect: Rect) -> [Rect] {
        guard !sizes.isEmpty, rect.w > 0, rect.h > 0 else { return [] }
        let total = sizes.reduce(0, +)
        guard total > 0 else { return sizes.map { _ in Rect(x: 0, y: 0, w: 0, h: 0) } }

        var result: [Rect] = []
        var remaining = sizes
        var currentRect = rect
        var currentTotal = total
        var row: [Double] = []

        func worst(_ row: [Double], side: Double) -> Double {
            let sum = row.reduce(0, +)
            guard sum > 0, side > 0,
                  let maxValue = row.max(), let minValue = row.min(), minValue > 0 else { return .infinity }
            return max(side * side * maxValue / (sum * sum), (sum * sum) / (side * side * minValue))
        }

        func placeRow() {
            let rowSum = row.reduce(0, +)
            guard rowSum > 0, currentTotal > 0 else { return }
            if currentRect.w >= currentRect.h {
                // 竖条：贴左放置，条宽按面积比例
                let stripWidth = rowSum / currentTotal * currentRect.w
                var offsetX = currentRect.x
                for value in row {
                    let width = value / rowSum * stripWidth
                    result.append(Rect(x: offsetX, y: currentRect.y, w: width, h: currentRect.h))
                    offsetX += width
                }
                currentRect.x += stripWidth
                currentRect.w -= stripWidth
            } else {
                // 横条：贴底放置
                let stripHeight = rowSum / currentTotal * currentRect.h
                var offsetY = currentRect.y
                for value in row {
                    let height = value / rowSum * stripHeight
                    result.append(Rect(x: currentRect.x, y: offsetY, w: currentRect.w, h: height))
                    offsetY += height
                }
                currentRect.y += stripHeight
                currentRect.h -= stripHeight
            }
            currentTotal -= rowSum
        }

        while !remaining.isEmpty {
            let side = min(currentRect.w, currentRect.h)
            if row.isEmpty {
                row.append(remaining.removeFirst())
                continue
            }
            let candidate = row + [remaining[0]]
            if worst(candidate, side: side) <= worst(row, side: side) {
                row.append(remaining.removeFirst())
            } else {
                placeRow()
                row = []
            }
        }
        if !row.isEmpty { placeRow() }
        return result
    }
}
