import Foundation

// MARK: - HTML önizleme üreticisi
//
// UYAP belgesini tek dosyalık, kendinden yeterli bir HTML belgesine çevirir.
// QuickLook'un yerleşik HTML görüntüleyicisi bu belgeyi işler; böylece
// uygulama eklentisi (PlugInKit) gerektirmeden özel bir önizleme üretilebilir.

public enum HTMLRenderer {

    public static func render(document: UDFDocument) -> String {
        var html = """
        <!DOCTYPE html>
        <html lang="tr"><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(document.title))</title>
        <style>
        \(styleSheet)
        </style>
        </head><body>
        <div class="wrap">
        \(header(document))
        \(summary(document))
        <div class="sheet">\(body(document))</div>
        \(footer(document))
        </div>
        </body></html>
        """
        return html
    }

    // MARK: Bölümler

    private static func header(_ document: UDFDocument) -> String {
        var subtitleParts: [String] = []
        if let court = document.court { subtitleParts.append(court) }
        subtitleParts.append(document.url.deletingPathExtension().lastPathComponent)

        var badges: [String] = []
        if !document.formatVersion.isEmpty {
            badges.append("<span class=\"badge indigo\">UYAP \(escape(document.formatVersion))</span>")
        }
        if document.signature.isSigned {
            badges.append("<span class=\"badge green\">İmzalı</span>")
        } else {
            badges.append("<span class=\"badge gray\">İmzasız</span>")
        }
        badges.append("<span class=\"badge gray\">\(document.paragraphCount) ¶</span>")

        return """
        <div class="card head">
          <div class="icon">\(iconSVG)</div>
          <div class="headtext">
            <div class="title">\(escape(document.title))</div>
            <div class="subtitle">\(escape(subtitleParts.joined(separator: "  •  ")))</div>
            <div class="badges">\(badges.joined())</div>
          </div>
        </div>
        """
    }

    private static func summary(_ document: UDFDocument) -> String {
        let fields = document.summaryFields
        guard !fields.isEmpty else { return "" }
        let rows = fields.map { field in
            """
            <div class="srow"><span class="skey">\(escape(field.key))</span><span class="sval">\(escape(field.value))</span></div>
            """
        }.joined()
        return "<div class=\"card summary\">\(rows)</div>"
    }

    private static func body(_ document: UDFDocument) -> String {
        var html = ""
        for paragraph in document.content.paragraphs {
            var style = ""
            switch paragraph.alignment {
            case .center: style += "text-align:center;"
            case .right: style += "text-align:right;"
            case .justify: style += "text-align:justify;"
            case .left: style += "text-align:left;"
            }
            if paragraph.leftIndent > 0 {
                style += "margin-left:\(String(format: "%.1f", paragraph.leftIndent))pt;"
            }

            var inner = ""
            for run in paragraph.runs {
                var text = escape(run.text)
                if run.bold { text = "<b>\(text)</b>" }
                if run.italic { text = "<i>\(text)</i>" }
                if run.underline { text = "<u>\(text)</u>" }

                let family = fontFamily(for: run.styleName, content: document.content)
                inner += "<span style=\"font-family:\(family);\">\(text)</span>"
            }
            html += "<p style=\"\(style)\">\(inner)</p>\n"
        }
        return html
    }

    private static func footer(_ document: UDFDocument) -> String {
        var parts = [document.url.lastPathComponent]
        parts.append(ByteCountFormatter.string(fromByteCount: document.fileSize, countStyle: .file))
        if let modified = document.modifiedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            parts.append(formatter.string(from: modified))
        }
        if let signer = document.signature.signerName {
            parts.append(signer)
        }
        return "<div class=\"footer\">\(escape(parts.joined(separator: "  •  ")))</div>"
    }

    private static func fontFamily(for styleName: String?, content: UDFContent) -> String {
        let family = styleName.flatMap { content.styles[$0] }?.family ?? "Dialog"
        if family.lowercased() == "dialog" {
            return "-apple-system, 'Helvetica Neue', sans-serif"
        }
        return "'\(family)', 'Times New Roman', serif"
    }

    // MARK: Yardımcılar

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let iconSVG = """
    <svg viewBox="0 0 24 24" width="34" height="34" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
      <path d="M14 2v6h6"/>
      <path d="M8 13h8"/><path d="M8 17h5"/>
    </svg>
    """

    private static let styleSheet = """
    :root {
      color-scheme: light dark;
      --bg: #f6f6f8;
      --card: #ffffff;
      --text: #1c1c1e;
      --muted: #6b6b70;
      --border: rgba(0,0,0,0.10);
      --sheet: #ffffff;
      --indigo: #4a4fd0;
      --green: #1f9d4d;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: transparent;
        --card: rgba(255,255,255,0.06);
        --text: #f2f2f5;
        --muted: #a0a0a6;
        --border: rgba(255,255,255,0.12);
        --sheet: rgba(255,255,255,0.04);
        --indigo: #8b8ff0;
        --green: #43c67b;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 0;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, 'Helvetica Neue', sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    .wrap { padding: 10px; }
    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 10px 12px;
      margin-bottom: 9px;
    }
    .head { display: flex; gap: 11px; align-items: flex-start; border-left: 3px solid var(--indigo); }
    .head .icon { color: var(--indigo); margin-top: 2px; flex: 0 0 auto; }
    .headtext { flex: 1 1 auto; min-width: 0; }
    .title { font-size: 13.5px; font-weight: 600; line-height: 1.25; }
    .subtitle { font-size: 11px; color: var(--muted); margin-top: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .badges { margin-top: 7px; display: flex; flex-wrap: wrap; gap: 5px; }
    .badge {
      font-size: 9.5px; font-weight: 600; padding: 2px 7px; border-radius: 9px;
      background: rgba(128,128,128,0.18); color: var(--muted); white-space: nowrap;
    }
    .badge.indigo { background: rgba(74,79,208,0.16); color: var(--indigo); }
    .badge.green { background: rgba(31,157,77,0.18); color: var(--green); }
    .srow { display: flex; gap: 8px; font-size: 11px; line-height: 1.5; }
    .skey { flex: 0 0 52px; font-size: 9px; font-weight: 600; color: var(--muted); text-transform: uppercase; letter-spacing: .3px; }
    .sval { flex: 1 1 auto; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .sheet {
      background: var(--sheet);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 12px 14px;
      font-size: 12px;
      line-height: 1.45;
    }
    .sheet p { margin: 0 0 5px 0; }
    .footer { font-size: 9.5px; color: var(--muted); padding: 2px 4px 6px 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    """
}
