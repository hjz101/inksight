import Foundation

/// 禁则表（避头尾）。
///
/// 契约（原生阶段冻结项，依 team-lead 开发包 #1 派单纪律 4）：
/// - `version` 必须参与 `TypographySignature` 哈希——禁则表一变断点就变，
///   不入签名会让旧 PageAnchor 永久复用错页，且只能靠重装 App 才"修好"。
/// - 本结构不可静默改版；要改走台账新编号。
public struct Kinsoku: Equatable, Sendable {

    /// 禁则表版本号（入 TypographySignature）。
    public let version: Int
    /// 行首禁则：这些字符不得作为一行的第一个字符（命中断点 → 标点悬挂到上一行行尾）。
    public let lineStartForbidden: Set<Character>
    /// 行尾禁则：这些字符不得作为一行的最后一个字符（命中断点 → 下移到下一行行首）。
    public let lineEndForbidden: Set<Character>

    public init(version: Int, lineStartForbidden: Set<Character>, lineEndForbidden: Set<Character>) {
        self.version = version
        self.lineStartForbidden = lineStartForbidden
        self.lineEndForbidden = lineEndForbidden
    }

    /// v1：中文出版惯例的避头尾集合。
    public static let v1 = Kinsoku(
        version: 1,
        lineStartForbidden: Set("，。、；：？！」』）】》〉…‥—～・!?),.;:]}\"'".characters()),
        lineEndForbidden: Set("「『（《【〈\"'([{".characters())
    )
}

private extension String {
    func characters() -> Set<Character> { Set(self) }
}
