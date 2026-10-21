import Foundation

// MARK: - Biçim modeli

public enum UDFAlignment: Int {
    case left = 0
    case center = 1
    case right = 2
    case justify = 3

    public init(rawAttribute: String?) {
        self = UDFAlignment(rawValue: Int(rawAttribute ?? "") ?? 0) ?? .left
    }
}

public struct UDFStyle {
    public let name: String
    public let family: String
    public let size: CGFloat
    public let bold: Bool
    public let italic: Bool
}

public struct UDFRun {
    public let text: String
    public let styleName: String?
    public let bold: Bool
    public let italic: Bool
    public let underline: Bool
}

public struct UDFParagraph {
    public let alignment: UDFAlignment
    public let leftIndent: CGFloat
    public let numbered: Bool
    public let listLevel: Int
    public let listID: String?
    public let runs: [UDFRun]

    public var plainText: String {
        runs.map(\.text).joined()
    }
}

public struct UDFContent {
    public let formatVersion: String
    public let masterText: String
    public let paragraphs: [UDFParagraph]
    public let styles: [String: UDFStyle]

    public init(formatVersion: String, masterText: String, paragraphs: [UDFParagraph], styles: [String: UDFStyle]) {
        self.formatVersion = formatVersion
        self.masterText = masterText
        self.paragraphs = paragraphs
        self.styles = styles
    }
}

// MARK: - SAX tabanlı content.xml ayrıştırıcı
//
// UYAP content.xml yapısı:
//   <template format_id="1.8">
//     <content><![CDATA[ ...ana metin... ]]></content>      <- UTF-16 ofset referanslarının tabanı
//     <properties><pageFormat .../></properties>
//     <elements>
//       <paragraph Alignment="1" LeftIndent="25.0">
//         <content bold="true" startOffset="24" length="45"/>  <- ana metinden dilim
//       </paragraph>
//     </elements>
//     <styles><style name="hvl-default" family="Times New Roman" size="12"/></styles>
//   </template>
//
// Not: UYAP Doküman Editörü Java tabanlı olduğu için ofsetler UTF-16 kod birimi
// cinsindendir. Bu yüzden metin UTF-16 dizisi üzerinden dilimlenir.

final class UDFXMLParser: NSObject, XMLParserDelegate {
    private struct RawRun {
        var styleName: String?
        var bold = false
        var italic = false
        var underline = false
        var startOffset = 0
        var length = 0
    }

    private struct RawParagraph {
        var alignment: UDFAlignment = .left
        var leftIndent: CGFloat = 0
        var numbered = false
        var listLevel = 0
        var listID: String?
        var runs: [RawRun] = []
    }

    private var elementStack: [String] = []
    private var masterBuffer = ""
    private var rawParagraphs: [RawParagraph] = []
    private var currentParagraph: RawParagraph?
    private var styles: [String: UDFStyle] = [:]
    private var formatVersion = ""

    func parse(data: Data) -> UDFContent? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { return nil }

        let utf16 = Array(masterBuffer.utf16)
        let paragraphs = rawParagraphs.map { raw -> UDFParagraph in
            let runs = raw.runs.compactMap { run -> UDFRun? in
                let lower = max(0, min(run.startOffset, utf16.count))
                let upper = max(lower, min(lower + run.length, utf16.count))
                guard upper > lower else { return nil }
                let slice = Array(utf16[lower..<upper])
                let text = String(decoding: slice, as: UTF16.self)
                return UDFRun(
                    text: text,
                    styleName: run.styleName,
                    bold: run.bold,
                    italic: run.italic,
                    underline: run.underline
                )
            }
            return UDFParagraph(
                alignment: raw.alignment,
                leftIndent: raw.leftIndent,
                numbered: raw.numbered,
                listLevel: raw.listLevel,
                listID: raw.listID,
                runs: runs
            )
        }

        return UDFContent(
            formatVersion: formatVersion,
            masterText: masterBuffer,
            paragraphs: paragraphs,
            styles: styles
        )
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let parent = elementStack.last

        switch elementName {
        case "template":
            formatVersion = attributeDict["format_id"] ?? ""

        case "style":
            let name = attributeDict["name"] ?? ""
            if !name.isEmpty {
                styles[name] = UDFStyle(
                    name: name,
                    family: attributeDict["family"] ?? "Dialog",
                    size: CGFloat(Double(attributeDict["size"] ?? "") ?? 12),
                    bold: (attributeDict["bold"] ?? "false").lowercased() == "true",
                    italic: (attributeDict["italic"] ?? "false").lowercased() == "true"
                )
            }

        case "paragraph":
            var paragraph = RawParagraph()
            paragraph.alignment = UDFAlignment(rawAttribute: attributeDict["Alignment"])
            paragraph.leftIndent = CGFloat(Double(attributeDict["LeftIndent"] ?? "") ?? 0)
            paragraph.numbered = (attributeDict["Numbered"] ?? "false").lowercased() == "true"
            paragraph.listLevel = Int(attributeDict["ListLevel"] ?? "") ?? 0
            paragraph.listID = attributeDict["ListId"]
            currentParagraph = paragraph

        case "content":
            if parent == "paragraph" {
                var run = RawRun()
                run.styleName = attributeDict["resolver"]
                run.bold = (attributeDict["bold"] ?? "false").lowercased() == "true"
                run.italic = (attributeDict["italic"] ?? "false").lowercased() == "true"
                run.underline = (attributeDict["underline"] ?? "false").lowercased() == "true"
                run.startOffset = Int(attributeDict["startOffset"] ?? "") ?? 0
                run.length = Int(attributeDict["length"] ?? "") ?? 0
                currentParagraph?.runs.append(run)
            }

        default:
            break
        }

        elementStack.append(elementName)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard elementStack.last == "content", elementStack.dropLast().last == "template" else { return }
        if let text = String(data: CDATABlock, encoding: .utf8) {
            masterBuffer += text
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard elementStack.last == "content", elementStack.dropLast().last == "template" else { return }
        masterBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "paragraph", let paragraph = currentParagraph {
            rawParagraphs.append(paragraph)
            currentParagraph = nil
        }
        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
    }
}
