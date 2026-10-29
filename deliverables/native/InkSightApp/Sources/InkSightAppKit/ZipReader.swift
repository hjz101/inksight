import Foundation
import Compression

// MARK: - ZipReader（最小 ZIP 读取，用于 epub 解包）

/// 最小 ZIP 读取器：**只做读取，不做写入**。
///
/// 为什么自己写而不用第三方：项目零外部依赖（全部 SPM 本地包 + 系统框架），
/// 而 epub 需要的能力很窄——读中心目录、取指定条目、解 deflate。
/// 自己实现约 150 行，比引入一个 zip 库更可控（且可审计）。
///
/// 支持：
/// - **Stored**（method 0，不压缩）；
/// - **Deflate**（method 8，用 `Compression` 框架解压）；
/// - **不加密**（epub 规范要求 DRM-free 场景；加密 epub 直接失败并说明原因）。
public struct ZipReader {

    /// 错误（每种都说明原因，不静默返回空）。
    public enum ZipError: LocalizedError, Equatable {
        case notZip
        case entryNotFound(String)
        case unsupportedCompression(UInt16)
        case encrypted
        case corrupted

        public var errorDescription: String? {
            switch self {
            case .notZip:                 return "不是有效的 zip 容器"
            case .entryNotFound(let n):   return "容器内找不到 \(n)"
            case .unsupportedCompression(let m): return "不支持的压缩方式 \(m)"
            case .encrypted:              return "容器已加密，无法读取"
            case .corrupted:              return "容器内容损坏"
            }
        }
    }

    /// 一个条目（中心目录项）。
    public struct Entry {
        public let name: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
        let flags: UInt16
    }

    private let data: Data
    public let entries: [Entry]

    /// 解析 ZIP 中心目录。
    public init(data: Data) throws {
        self.data = data
        guard data.count >= 22 else { throw ZipError.notZip }
        // EOCD 签名 0x06054b50，从尾部向前搜（注释长度 ≤ 65535）
        guard let eocd = Self.findEOCD(in: data) else { throw ZipError.notZip }

        let entryCount = Int(Self.u16(data, eocd + 10))
        var cdOffset = Int(Self.u32(data, eocd + 16))

        var parsed: [Entry] = []
        parsed.reserveCapacity(entryCount)
        for _ in 0..<entryCount {
            guard cdOffset + 46 <= data.count,
                  Self.u32(data, cdOffset) == 0x0201_4b50 else { break }
            let flags = Self.u16(data, cdOffset + 8)
            let method = Self.u16(data, cdOffset + 10)
            let compressed = Int(Self.u32(data, cdOffset + 20))
            let uncompressed = Int(Self.u32(data, cdOffset + 24))
            let nameLen = Int(Self.u16(data, cdOffset + 28))
            let extraLen = Int(Self.u16(data, cdOffset + 30))
            let commentLen = Int(Self.u16(data, cdOffset + 32))
            let localOffset = Int(Self.u32(data, cdOffset + 42))

            let nameStart = cdOffset + 46
            guard nameStart + nameLen <= data.count else { throw ZipError.corrupted }
            let name = String(decoding: data[nameStart..<(nameStart + nameLen)], as: UTF8.self)

            parsed.append(Entry(name: name,
                                compressionMethod: method,
                                compressedSize: compressed,
                                uncompressedSize: uncompressed,
                                localHeaderOffset: localOffset,
                                flags: flags))
            cdOffset = nameStart + nameLen + extraLen + commentLen
        }
        self.entries = parsed
    }

    /// 读取指定条目的字节（解压后）。
    public func read(_ name: String) throws -> Data {
        guard let entry = entries.first(where: { $0.name == name }) else {
            throw ZipError.entryNotFound(name)
        }
        return try read(entry)
    }

    /// 条目名以某后缀结尾的第一个（epub 的 OPF 路径常带目录前缀）。
    public func readFirst(matching suffix: String) throws -> (name: String, data: Data) {
        guard let entry = entries.first(where: { $0.name.hasSuffix(suffix) }) else {
            throw ZipError.entryNotFound(suffix)
        }
        return (entry.name, try read(entry))
    }

    private func read(_ entry: Entry) throws -> Data {
        // 加密位（bit 0）
        guard entry.flags & 0x0001 == 0 else { throw ZipError.encrypted }

        // 本地头：签名 0x04034b50，长度 30 + name + extra
        let lh = entry.localHeaderOffset
        guard lh + 30 <= data.count, Self.u32(data, lh) == 0x0403_4b50 else {
            throw ZipError.corrupted
        }
        let nameLen = Int(Self.u16(data, lh + 26))
        let extraLen = Int(Self.u16(data, lh + 28))
        let payloadStart = lh + 30 + nameLen + extraLen
        guard payloadStart + entry.compressedSize <= data.count else {
            throw ZipError.corrupted
        }
        let payload = data[payloadStart..<(payloadStart + entry.compressedSize)]

        switch entry.compressionMethod {
        case 0:
            return Data(payload)
        case 8:
            return try Self.inflate(Data(payload), expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(entry.compressionMethod)
        }
    }

    // MARK: - 解压

    /// raw deflate 解压（`Compression` 框架的 DEFLATE 即 raw deflate）。
    static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written: Int = output.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src in
                guard let dstPtr = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcPtr = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstPtr, expectedSize,
                                                 srcPtr, input.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw ZipError.corrupted }
        return output.prefix(written)
    }

    // MARK: - 二进制读取辅助（小端）

    static func u16(_ d: Data, _ o: Int) -> UInt16 {
        guard o + 2 <= d.count else { return 0 }
        return UInt16(d[d.startIndex + o]) | (UInt16(d[d.startIndex + o + 1]) << 8)
    }

    static func u32(_ d: Data, _ o: Int) -> UInt32 {
        guard o + 4 <= d.count else { return 0 }
        return UInt32(d[d.startIndex + o])
            | (UInt32(d[d.startIndex + o + 1]) << 8)
            | (UInt32(d[d.startIndex + o + 2]) << 16)
            | (UInt32(d[d.startIndex + o + 3]) << 24)
    }

    /// 从尾部找 EOCD 签名。
    static func findEOCD(in data: Data) -> Int? {
        let maxComment = 65535
        let start = max(0, data.count - 22 - maxComment)
        var i = data.count - 22
        while i >= start {
            if u32(data, i) == 0x0605_4b50 { return i }
            i -= 1
        }
        return nil
    }
}
