import Darwin
import Foundation

/// 网络指标采集（原生 API：sysctl NET_RT_IFLIST2，64 位计数器，无截断风险）。
enum NetworkMetrics {
    struct Counter {
        var bytesIn: UInt64
        var bytesOut: UInt64
    }

    /// 所有非回环接口的收发字节累计值。
    static func counter() -> Counter {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: size_t = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0 else {
            return Counter(bytesIn: 0, bytesOut: 0)
        }
        var buffer = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, u_int(mib.count), &buffer, &len, nil, 0) == 0 else {
            return Counter(bytesIn: 0, bytesOut: 0)
        }

        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= buffer.count {
            let header = buffer.withUnsafeBytes { raw -> if_msghdr in
                raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            }
            if header.ifm_type == RTM_IFINFO2 {
                let header2 = buffer.withUnsafeBytes { raw -> if_msghdr2 in
                    raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                }
                // 接口名不在结构体内，通过索引查询（if_indextoname）
                var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                let name = if_indextoname(UInt32(header2.ifm_index), &nameBuffer).map { String(cString: $0) } ?? ""
                if name != "lo0" {
                    bytesIn += header2.ifm_data.ifi_ibytes
                    bytesOut += header2.ifm_data.ifi_obytes
                }
            }
            guard header.ifm_msglen > 0 else { break }
            offset += Int(header.ifm_msglen)
        }
        return Counter(bytesIn: bytesIn, bytesOut: bytesOut)
    }

    /// 两次计数之间的速率（字节/秒）。计数器重置（如网络重连）时不产生负速率。
    static func rate(prev: Counter, curr: Counter, elapsed: TimeInterval) -> (down: Double, up: Double) {
        guard elapsed > 0 else { return (0, 0) }
        let down = curr.bytesIn > prev.bytesIn ? Double(curr.bytesIn - prev.bytesIn) / elapsed : 0
        let up = curr.bytesOut > prev.bytesOut ? Double(curr.bytesOut - prev.bytesOut) / elapsed : 0
        return (down, up)
    }
}
