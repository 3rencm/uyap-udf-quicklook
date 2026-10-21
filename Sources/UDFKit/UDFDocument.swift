import Foundation
import AppKit

// MARK: - Belge modeli

public struct UDFKeyValue {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public enum UDFDocumentError: LocalizedError {
    case unreadable(String)
    case missingContent
    case parseFailed

    public var errorDescription: String? {
        switch self {
        case .unreadable(let detail): return detail
        case .missingContent: return "Bu dosya UYAP UDF belgesi değil (content.xml bulunamadı)."
        case .parseFailed: return "Belge içeriği ayrıştırılamadı."
        }
    }
}

public struct UDFDocument {
    public let url: URL
    public let fileSize: Int64
    public let modifiedAt: Date?
    public let formatVersion: String
    public let content: UDFContent
    public let signature: SignatureInfo
    public let archiveEntries: [String]

    public init(
        url: URL,
        fileSize: Int64,
        modifiedAt: Date?,
        formatVersion: String,
        content: UDFContent,
        signature: SignatureInfo,
        archiveEntries: [String]
    ) {
        self.url = url
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.formatVersion = formatVersion
        self.content = content
        self.signature = signature
        self.archiveEntries = archiveEntries
    }

    // MARK: Türetilmiş alanlar

    public var plainText: String { content.masterText }

    public var paragraphCount: Int { content.paragraphs.count }

    public var characterCount: Int { content.masterText.count }

    public var wordCount: Int {
        content.masterText.split(whereSeparator: { $0.isWhitespace }).count
    }

    public var lines: [String] {
        content.masterText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Belgenin başlığı: ilk anlamlı satır.
    public var title: String {
        if let first = lines.first(where: { !$0.isEmpty }) {
            return first.count > 90 ? String(first.prefix(90)) + "…" : first
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Mahkeme adı: "MAHKEME" içeren ilk büyük harfli satır.
    public var court: String? {
        let candidates = lines.filter { line in
            let upper = line.uppercased()
            return upper.contains("MAHKEME") && upper == line && line.count > 5
        }
        guard let value = candidates.first else { return nil }
        return value.replacingOccurrences(of: "'NE", with: "")
            .replacingOccurrences(of: "'NE ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// DAVACI / DAVALI / KONU gibi başlık satırlarından özet çıkarır.
    public var summaryFields: [UDFKeyValue] {
        let interesting: Set<String> = ["DAVACI", "DAVALI", "VEKİLİ", "KONU", "DAVA KONUSU", "TALEP"]
        var fields: [UDFKeyValue] = []

        for line in lines {
            guard line.count > 6 else { continue }
            let separatorRange = line.range(of: ":") ?? line.range(of: "\t:")
            guard let separator = separatorRange else { continue }
            let key = line[..<separator.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard interesting.contains(key) else { continue }

            let value = line[separator.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let shortened = value.count > 120 ? String(value.prefix(120)) + "…" : value
            if !fields.contains(where: { $0.key == key }) {
                fields.append(UDFKeyValue(key: key, value: shortened))
            }
        }
        return fields
    }

    // MARK: Yükleme

    public static func load(url: URL) throws -> UDFDocument {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = attributes?[.modificationDate] as? Date

        let archive: ZipArchive
        do {
            archive = try ZipArchive(url: url)
        } catch {
            throw UDFDocumentError.unreadable(
                "Dosya açılamadı. UYAP .udf dosyaları ZIP paketi biçimindedir.\n\(error.localizedDescription)"
            )
        }

        guard archive.contains("content.xml") else {
            throw UDFDocumentError.missingContent
        }

        let contentData = try archive.data(for: "content.xml")
        guard let content = UDFXMLParser().parse(data: contentData) else {
            throw UDFDocumentError.parseFailed
        }

        var signature = SignatureInfo.unsigned
        if archive.contains("sign.sgn"), let signData = try? archive.data(for: "sign.sgn") {
            signature = SignatureInfo.parse(data: signData)
        }

        return UDFDocument(
            url: url,
            fileSize: size,
            modifiedAt: modified,
            formatVersion: content.formatVersion,
            content: content,
            signature: signature,
            archiveEntries: archive.entryOrder
        )
    }
}

// MARK: - Metin biçimlendirme

public enum UDFTextRenderer {

    /// UDF belgesini zengin metin (NSAttributedString) olarak oluşturur.
    public static func attributedString(for content: UDFContent) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var listCounters: [String: Int] = [:]

        for paragraph in content.paragraphs {
            let paragraphStyle = NSMutableParagraphStyle()
            switch paragraph.alignment {
            case .left: paragraphStyle.alignment = .left
            case .center: paragraphStyle.alignment = .center
            case .right: paragraphStyle.alignment = .right
            case .justify: paragraphStyle.alignment = .justified
            }
            paragraphStyle.lineHeightMultiple = 1.12
            paragraphStyle.paragraphSpacing = 5
            paragraphStyle.paragraphSpacingBefore = 2
            paragraphStyle.headIndent = paragraph.leftIndent
            paragraphStyle.firstLineHeadIndent = paragraph.leftIndent
            paragraphStyle.lineBreakMode = .byWordWrapping

            var prefix = ""
            if paragraph.numbered {
                let key = paragraph.listID ?? "default"
                listCounters[key, default: 0] += 1
                let counter = listCounters[key] ?? 1
                prefix = "\(counter). "
                paragraphStyle.firstLineHeadIndent = paragraph.leftIndent
                paragraphStyle.headIndent = paragraph.leftIndent + 18
            }

            var prefixAttributes: [NSAttributedString.Key: Any] = [:]
            if !prefix.isEmpty {
                let baseFont = font(for: paragraph.runs.first?.styleName, content: content, bold: true)
                prefixAttributes = [
                    .font: baseFont,
                    .paragraphStyle: paragraphStyle
                ]
                result.append(NSAttributedString(string: prefix, attributes: prefixAttributes))
            }

            let runs = paragraph.runs
            for (index, run) in runs.enumerated() {
                var text = run.text
                if index == runs.count - 1 {
                    if text.hasSuffix("\r\n") {
                        text.removeLast(2)
                    } else if text.hasSuffix("\n") {
                        text.removeLast(1)
                    }
                }
                guard !text.isEmpty else { continue }

                let attributes = attributes(for: run, content: content, paragraphStyle: paragraphStyle)
                result.append(NSAttributedString(string: text, attributes: attributes))
            }

            // Paragraf sonu: satır sonu ile bir sonraki paragraf arasında boşluk bırak.
            result.append(
                NSAttributedString(
                    string: "\n",
                    attributes: [
                        .font: font(for: runs.first?.styleName, content: content),
                        .paragraphStyle: paragraphStyle
                    ]
                )
            )
        }

        return result
    }

    private static func attributes(
        for run: UDFRun,
        content: UDFContent,
        paragraphStyle: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: run.styleName, content: content, bold: run.bold, italic: run.italic),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]
        if run.underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    private static func font(
        for styleName: String?,
        content: UDFContent,
        bold: Bool = false,
        italic: Bool = false
    ) -> NSFont {
        let style = styleName.flatMap { content.styles[$0] }
        let family = style?.family ?? "Dialog"
        let size = max(9, min(style?.size ?? 12, 22))

        // NSFontDescriptorTraitBold = 1<<1, NSFontDescriptorTraitItalic = 1<<0
        let boldTrait = NSFontDescriptor.SymbolicTraits(rawValue: 1 << 1)
        let italicTrait = NSFontDescriptor.SymbolicTraits(rawValue: 1 << 0)

        var traits = NSFontDescriptor.SymbolicTraits()
        if bold || style?.bold == true { traits.insert(boldTrait) }
        if italic || style?.italic == true { traits.insert(italicTrait) }

        if family.lowercased() == "dialog" {
            // Java "Dialog" mantıksal yazı tipi için sistem yazı tipine düş.
            let base = NSFont.systemFont(
                ofSize: size,
                weight: traits.contains(boldTrait) ? .bold : .regular
            )
            if traits.contains(italicTrait) {
                let italicDescriptor = base.fontDescriptor.withSymbolicTraits(
                    base.fontDescriptor.symbolicTraits.union(italicTrait)
                )
                return NSFont(descriptor: italicDescriptor, size: size) ?? base
            }
            return base
        }

        // Belgede tanımlı yazı tipi ailesi (örn. Times New Roman)
        if let base = NSFont(name: family, size: size) {
            if traits.isEmpty {
                return base
            }
            let descriptor = base.fontDescriptor.withSymbolicTraits(
                base.fontDescriptor.symbolicTraits.union(traits)
            )
            return NSFont(descriptor: descriptor, size: size) ?? base
        }

        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: traits
        ])
        return NSFont(descriptor: descriptor, size: size)
            ?? NSFont(name: family, size: size)
            ?? NSFont.systemFont(ofSize: size)
    }
}
