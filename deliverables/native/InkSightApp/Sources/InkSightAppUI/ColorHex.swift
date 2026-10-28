import SwiftUI

// MARK: - Color(hexString:)（主题色 token 解析）

/// 十六进制颜色字符串 → `Color`（`#RRGGBB`；解析失败回落中性灰）。
///
/// 与 `ReaderPageCanvas.cgColor(hex:)` **同源口径**——主题色只在这一处解析，
/// 避免两套 hex 解析器产生色差（DESIGN §3 判据要求「四项同时变」，
/// 若解析器不一致，观感上会出现"某项没变"的假象）。
extension Color {
    init(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: .whitespaces)
        let v = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
        guard v.count == 6, let n = UInt32(v, radix: 16) else {
            self = Color(white: 0.5)
            return
        }
        self = Color(
            red: Double((n >> 16) & 0xFF) / 255,
            green: Double((n >> 8) & 0xFF) / 255,
            blue: Double(n & 0xFF) / 255
        )
    }
}
