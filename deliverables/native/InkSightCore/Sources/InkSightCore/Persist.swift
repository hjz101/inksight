import Foundation

// MARK: - Persist（落盘单门，总册第 6 章「三个门面」之二，架构勘误 E-04）

/// 落盘门面：**所有磁盘写入必须经 `Persist.write`**。
///
/// 目的：把「不得落盘什么」从一条条款变成**一个可 grep 的调用点清单**——全部写盘
/// 都从这里过，每条路径声明 payload 类型。绕过本门面直写 `FileManager` 即违规
/// （架构勘误 E-04；单测以「源码扫描：业务层无裸 `.write(to:`」兜底）。
///
/// 核心设计（架构勘误 E-04 原文）：**「第三方正文」这个类型在产品层不允许存在**——
/// 不是禁用，是**类型里没有**。`Payload` 枚举只允许：用户文件 / 进度 / 笔记 / 排版偏好 /
/// 动效偏好 / 结构元数据（可重建）。任何"把正文落盘"的意图在编译期就无法表达。
public enum Persist {

    /// 落盘负载类型。**新增类型必须走台账编号**（类型层变更）。
    ///
    /// ⚠️ 刻意不提供 `.thirdPartyContent` / `.bodyText` 等 case——第三方正文在类型层
    /// 不存在（E-04）。"把正文落盘"在本门面内无法表达。
    public enum Payload: Sendable {
        /// 用户本地导入的原始文件（用户自己拥有，落盘合法）。
        case userFile
        /// 阅读进度（`charOffset + fingerprint`，定位铁律）。
        case readingProgress
        /// 用户笔记 / 划线 / 书签。
        case notes
        /// 排版偏好（字号/行距/边距等 8 字段，用户偏好可备份）。
        case typographyPreference
        /// 动效开关偏好（用户偏好可备份）。
        case motionPreference
        /// 结构元数据（分页锚点/分章锚点/在线进度映射——**可重建**，排除 iCloud 备份）。
        case structuralMetadata
    }

    /// 写入结果。
    public enum WriteError: Error, Equatable, Sendable {
        case createDirectoryFailed
        case writeFailed
    }

    /// **唯一写盘入口**：原子写。
    ///
    /// - 先建目录（若不存在），再原子写。
    /// - `payload` 声明数据类型——审计与 grep 用（E-04：调用点清单）。
    /// - `excludedFromBackup`：结构性/可重建数据排除备份（NFR-03 备份纪律）；
    ///   用户偏好（排版/动效）**不**排除（应随 iCloud 恢复）。
    @discardableResult
    public static func write(_ data: Data, to url: URL,
                             payload: Payload,
                             excludedFromBackup: Bool) -> Result<Void, WriteError> {
        switch prepareDirectory(for: url) {
        case .failure(let error): return .failure(error)
        case .success: break
        }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            return .failure(.writeFailed)
        }
        if excludedFromBackup {
            applyExcludedFromBackup(to: url)
        }
        return .success(())
    }

    /// 为写盘准备目录（SQLite 等以文件句柄打开的写入也经此建目录，保证"建目录"同样过门面）。
    @discardableResult
    public static func prepareDirectory(for url: URL) -> Result<Void, WriteError> {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .failure(.createDirectoryFailed)
        }
        return .success(())
    }

    /// 排除备份：对文件与其所在目录设 `NSURLIsExcludedFromBackupKey`。
    public static func applyExcludedFromBackup(to url: URL) {
        var fileValues = URLResourceValues()
        fileValues.isExcludedFromBackup = true
        var fileURL = url
        try? fileURL.setResourceValues(fileValues)

        var dirURL = url.deletingLastPathComponent()
        var dirValues = URLResourceValues()
        dirValues.isExcludedFromBackup = true
        try? dirURL.setResourceValues(dirValues)
    }
}
