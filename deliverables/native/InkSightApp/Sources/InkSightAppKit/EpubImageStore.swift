import Foundation
import InkSightCore

// MARK: - EpubImageStore（FR-018-ac b：图片字节缓存与按序号取图）

/// epub 图片缓存（占位块点击进全屏原图的数据源）。
///
/// 存储策略：
/// - 目录 `Caches/InkSight/EpubImages/{bookHash}/`
/// - 文件名按**正文出现顺序**编号：`0.jpg`、`1.png`…（与占位标记顺序一一对应）
/// - 经 `Persist` 的 `.structuralMetadata`（可重建的派生数据）+ 排除备份
///
/// **为什么按序号而不是原名**：占位标记里只有"第几个图"，没有原文件名；
/// 按序号命名让"标记第 i 个 → 第 i 个文件"成为**结构保证**，不需要额外索引表。
public enum EpubImageStore {

    /// 某本书的图片缓存目录。
    public static func directory(for bookID: String) throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let name = String(format: "%016llx", Fingerprint.fnv1a64(bookID))
        let dir = base.appendingPathComponent("InkSight/EpubImages/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 保存某书按顺序的全部图片（`nil` 项跳过，但**序号保持**）。
    ///
    /// - Returns: 实际写入的图片数（便于诊断"图文混排书有几张图能看"）。
    @discardableResult
    public static func save(images: [Data?], bookID: String) throws -> Int {
        let dir = try directory(for: bookID)
        var written = 0
        for (index, data) in images.enumerated() {
            guard let data, !data.isEmpty else { continue }
            let url = dir.appendingPathComponent("\(index)\(ext(for: data))")
            try Persist.write(data, to: url, payload: .structuralMetadata,
                              excludedFromBackup: true).get()
            written += 1
        }
        return written
    }

    /// 按序号取图（全屏查看用）。
    ///
    /// 文件名扩展名按实际字节猜（存的时候也按同样的规则），
    /// 故这里逐个候选扩展名尝试——**不做"先存索引表"那种额外状态**。
    public static func image(at index: Int, bookID: String) -> Data? {
        guard let dir = try? directory(for: bookID) else { return nil }
        for ext in [".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ""] {
            let url = dir.appendingPathComponent("\(index)\(ext)")
            if let data = try? Data(contentsOf: url), !data.isEmpty { return data }
        }
        return nil
    }

    /// 清除某书图片缓存。
    public static func clear(bookID: String) {
        guard let dir = try? directory(for: bookID) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// 按 magic bytes 猜扩展名（存/取同一规则）。
    static func ext(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(4))
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8 { return ".jpg" }
        if bytes.count >= 4, bytes[0] == 0x89, bytes[1] == 0x50,
           bytes[2] == 0x4E, bytes[3] == 0x47 { return ".png" }
        if bytes.count >= 3, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 { return ".gif" }
        if bytes.count >= 2, bytes[0] == 0x42, bytes[1] == 0x4D { return ".bmp" }
        if bytes.count >= 4, bytes[0] == 0x52, bytes[1] == 0x49,
           bytes[2] == 0x46, bytes[3] == 0x46 { return ".webp" }
        return ".jpg"   // 兜底
    }
}
