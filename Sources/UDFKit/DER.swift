import Foundation

// MARK: - Minimal DER / ASN.1 okuyucu
//
// UYAP .udf dosyalarındaki sign.sgn, PKCS#7 (CMS SignedData) formatında bir
// imzadır. İmza özetinin (imzalayan kişi, imza tarihi) çıkarılabilmesi için
// çok küçük bir DER ağaç ayrıştırıcı kullanılır.

struct DERNode {
    let tag: UInt8
    let headerLength: Int
    let value: Data
    let children: [DERNode]

    var isConstructed: Bool { tag & 0x20 != 0 }

    /// Başlıksız (tag) içerik ofseti
    var contentOffset: Int { 0 }
}

enum DERParser {
    /// Verilen DER blob'unu ağaç olarak ayrıştırır.
    static func parse(_ data: Data) -> [DERNode] {
        var nodes: [DERNode] = []
        var index = 0
        let bytes = [UInt8](data)

        while index < bytes.count {
            guard let (node, next) = parseNode(bytes, at: index) else { break }
            nodes.append(node)
            index = next
        }
        return nodes
    }

    private static func parseNode(_ bytes: [UInt8], at index: Int) -> (DERNode, Int)? {
        guard index < bytes.count else { return nil }
        let tag = bytes[index]
        var cursor = index + 1

        // Uzun form
        if tag & 0x1F == 0x1F {
            while cursor < bytes.count {
                let byte = bytes[cursor]
                cursor += 1
                if byte & 0x80 == 0 { break }
            }
        }

        guard cursor < bytes.count else { return nil }
        var length = Int(bytes[cursor])
        cursor += 1

        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 8, cursor + count <= bytes.count else { return nil }
            length = 0
            for offset in 0..<count {
                length = (length << 8) | Int(bytes[cursor + offset])
            }
            cursor += count
        }

        guard length >= 0, cursor + length <= bytes.count else { return nil }
        let value = Data(bytes[cursor..<(cursor + length)])
        let end = cursor + length

        var children: [DERNode] = []
        if tag & 0x20 != 0 {
            var inner = cursor
            while inner < end {
                guard let (child, next) = parseNode(bytes, at: inner) else { break }
                children.append(child)
                inner = next
            }
        }

        return (DERNode(tag: tag, headerLength: cursor - index, value: value, children: children), end)
    }
}

// MARK: - Kolaylık yardımcıları

extension DERNode {
    /// Distinguished Name içinden CN (Common Name) değerini döndürür.
    func commonName() -> String? {
        // Name ::= SEQUENCE OF RelativeDistinguishedName
        for rdn in children where rdn.tag == 0x31 {
            for attribute in rdn.children where attribute.tag == 0x30 {
                let parts = attribute.children
                guard parts.count >= 2 else { continue }
                let oid = parts[0].value
                if oid == DERNode.oidCommonName {
                    return parts[1].stringValue()
                }
            }
        }
        return nil
    }

    func stringValue() -> String? {
        switch tag {
        case 0x0C, 0x13, 0x16, 0x14, 0x1E: // UTF8String, PrintableString, IA5String, TeletexString, BMPString
            if tag == 0x1E {
                return String(data: value, encoding: .utf16BigEndian)
            }
            return String(data: value, encoding: .utf8)
        case 0x17: // UTCTime
            return formatUTCTime(String(data: value, encoding: .ascii) ?? "")
        case 0x18: // GeneralizedTime
            return formatGeneralizedTime(String(data: value, encoding: .ascii) ?? "")
        default:
            return nil
        }
    }

    static let oidCommonName = Data([0x55, 0x04, 0x03]) // 2.5.4.3

    private func formatUTCTime(_ raw: String) -> String? {
        let digits = raw.replacingOccurrences(of: "Z", with: "")
        guard digits.count >= 10 else { return nil }
        let year = 2000 + (Int(digits.prefix(2)) ?? 0)
        let month = Int(digits.dropFirst(2).prefix(2)) ?? 1
        let day = Int(digits.dropFirst(4).prefix(2)) ?? 1
        let hour = Int(digits.dropFirst(6).prefix(2)) ?? 0
        let minute = Int(digits.dropFirst(8).prefix(2)) ?? 0
        let second = digits.count >= 12 ? (Int(digits.dropFirst(10).prefix(2)) ?? 0) : 0
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d UTC", year, month, day, hour, minute, second)
    }

    private func formatGeneralizedTime(_ raw: String) -> String? {
        let digits = raw.replacingOccurrences(of: "Z", with: "")
        guard digits.count >= 10 else { return nil }
        let year = Int(digits.prefix(4)) ?? 0
        let month = Int(digits.dropFirst(4).prefix(2)) ?? 1
        let day = Int(digits.dropFirst(6).prefix(2)) ?? 1
        let hour = Int(digits.dropFirst(8).prefix(2)) ?? 0
        let minute = Int(digits.dropFirst(10).prefix(2)) ?? 0
        let second = digits.count >= 12 ? (Int(digits.dropFirst(12).prefix(2)) ?? 0) : 0
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d UTC", year, month, day, hour, minute, second)
    }
}

extension DERNode {
    /// Ağaç içinde verilen etiketlere sahip tüm düğümleri yineler (derinlik öncelikli).
    func descendants(where predicate: (DERNode) -> Bool) -> [DERNode] {
        var result: [DERNode] = []
        for child in children {
            if predicate(child) { result.append(child) }
            result.append(contentsOf: child.descendants(where: predicate))
        }
        return result
    }
}
