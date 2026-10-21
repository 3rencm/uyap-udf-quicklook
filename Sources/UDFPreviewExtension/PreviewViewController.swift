import Cocoa
import QuickLookUI
import UniformTypeIdentifiers
import UDFKit

// MARK: - Yardımcı görünümler

/// Üstten alta doğru yerleşim için ters çevrilmiş kök görünüm.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Yuvarlatılmış köşeli, isteğe bağlı vurgu şeritli kart.
final class CardView: NSView {
    var cornerRadius: CGFloat = 12
    var fillColor: NSColor = .controlBackgroundColor
    var strokeColor: NSColor = .separatorColor
    var accentColor: NSColor?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)

        if let gradient = NSGradient(
            starting: fillColor.blended(withFraction: 0.05, of: .labelColor) ?? fillColor,
            ending: fillColor
        ) {
            gradient.draw(in: path, angle: -90)
        } else {
            fillColor.setFill()
            path.fill()
        }

        if let accentColor {
            accentColor.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 0, y: 0, width: 3, height: bounds.height),
                xRadius: 1.5,
                yRadius: 1.5
            ).fill()
        }

        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// Yatay rozet satırı (kendi çizimiyle, Auto Layout'a bağımlı değil).
final class BadgeRowView: NSView {
    struct Badge {
        let text: String
        let fill: NSColor
        let textColor: NSColor
    }

    private var badges: [Badge] = []
    private let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private let height: CGFloat = 17
    private let padding: CGFloat = 7
    private let spacing: CGFloat = 5

    override var isFlipped: Bool { true }

    func setBadges(_ badges: [Badge]) {
        self.badges = badges
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    private func size(for badge: Badge) -> NSSize {
        (badge.text as NSString).size(withAttributes: [.font: font])
    }

    override var intrinsicContentSize: NSSize {
        var width: CGFloat = 0
        for badge in badges {
            width += size(for: badge).width + padding * 2 + spacing
        }
        return NSSize(width: max(0, width - spacing), height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        var x: CGFloat = 0
        for badge in badges {
            let textSize = size(for: badge)
            let width = textSize.width + padding * 2
            let rect = NSRect(x: x, y: 0, width: width, height: height)

            badge.fill.setFill()
            NSBezierPath(
                roundedRect: rect,
                xRadius: height / 2,
                yRadius: height / 2
            ).fill()

            (badge.text as NSString).draw(
                at: NSPoint(x: x + padding, y: (height - textSize.height) / 2),
                withAttributes: [.font: font, .foregroundColor: badge.textColor]
            )

            x += width + spacing
        }
    }
}

// MARK: - Önizleme denetleyicisi (Preview Extension principal class)

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {

    private var fileURL: URL?
    private var document: UDFDocument?
    private var failureMessage: String?

    private let headerCard = CardView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let badgeRow = BadgeRowView()
    private let summaryCard = CardView()
    private var summaryRows: [(key: NSTextField, value: NSTextField)] = []
    private let sheetView = CardView()
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let footerLabel = NSTextField(labelWithString: "")
    private let errorCard = CardView()
    private let errorTitle = NSTextField(labelWithString: "")
    private let errorMessage = NSTextField(wrappingLabelWithString: "")

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: QLPreviewingController

    /// QuickLook, önizlemeyi göstermeden hemen önce bu metodi çağırır.
    func preparePreviewOfFile(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        PreviewLog.write("preparePreviewOfFile çağrıldı: \(url.path)")
        fileURL = url
        loadDocument()
        if isViewLoaded {
            populate()
        }
        completionHandler(nil)
    }

    // MARK: NSExtensionRequestHandling

    /// Eklenti sistemi isteği principal class'a bu şekilde iletir.
    override func beginRequest(with context: NSExtensionContext) {
        PreviewLog.write("beginRequest çağrıldı")
        guard let item = context.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first
        else {
            PreviewLog.write("istek girdisi bulunamadı")
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] value, error in
            guard let url = value as? URL else {
                PreviewLog.write("dosya URL'si alınamadı: \(String(describing: error))")
                return
            }
            DispatchQueue.main.async {
                guard let self else { return }
                PreviewLog.write("önizleme hazırlanıyor: \(url.path)")
                self.fileURL = url
                self.loadDocument()
                if self.isViewLoaded {
                    self.populate()
                }
            }
        }
    }

    // MARK: Veri yükleme

    private func loadDocument() {
        guard let fileURL else { return }
        do {
            document = try UDFDocument.load(url: fileURL)
            failureMessage = nil
        } catch {
            document = nil
            failureMessage = describe(error)
        }
    }

    private func describe(_ error: Error) -> String {
        let underlying = (error as? UDFDocumentError)?.errorDescription ?? error.localizedDescription
        let bytes = (try? Data(contentsOf: fileURL ?? URL(fileURLWithPath: "/"), options: .mappedIfSafe)) ?? Data()
        if bytes.count >= 2, bytes[bytes.startIndex] == 0x50, bytes[bytes.startIndex + 1] == 0x4B {
            return "Bu dosya bir ZIP paketi, ancak UYAP UDF belgesi değil.\n\n\(underlying)"
        }
        if bytes.count >= 2, bytes[bytes.startIndex] == 0x53, bytes[bytes.startIndex + 1] == 0x54 {
            return "Bu dosya bir UDF disk imajı. UYAP belge önizlemesi yalnızca UYAP .udf belgeleri için geçerlidir."
        }
        return underlying
    }

    // MARK: Görünüm kurulumu

    override func loadView() {
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 360, height: 520))
        view = root

        configureHeader()
        configureSummary()
        configureSheet()
        configureFooter()
        configureError()

        for subview in [headerCard, summaryCard, sheetView, footerLabel, errorCard] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = true
            root.addSubview(subview)
        }
    }

    private func configureHeader() {
        headerCard.fillColor = .controlBackgroundColor
        headerCard.accentColor = .systemIndigo

        iconView.image = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: nil)
        iconView.contentTintColor = .systemIndigo
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = true

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2

        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        headerCard.addSubview(iconView)
        headerCard.addSubview(titleLabel)
        headerCard.addSubview(subtitleLabel)
        headerCard.addSubview(badgeRow)
    }

    private func configureSummary() {
        summaryCard.fillColor = .controlBackgroundColor
        summaryCard.strokeColor = .separatorColor
    }

    private func configureSheet() {
        sheetView.fillColor = .textBackgroundColor
        sheetView.strokeColor = .separatorColor
        sheetView.cornerRadius = 8

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        sheetView.addSubview(scrollView)
    }

    private func configureFooter() {
        footerLabel.font = NSFont.systemFont(ofSize: 9.5)
        footerLabel.textColor = .tertiaryLabelColor
        footerLabel.lineBreakMode = .byTruncatingMiddle
    }

    private func configureError() {
        errorCard.fillColor = .controlBackgroundColor
        errorCard.strokeColor = .separatorColor
        errorTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        errorTitle.textColor = .labelColor
        errorMessage.font = NSFont.systemFont(ofSize: 11)
        errorMessage.textColor = .secondaryLabelColor
        errorMessage.isSelectable = true
        errorCard.addSubview(errorTitle)
        errorCard.addSubview(errorMessage)
    }

    // MARK: İçerik

    override func viewDidLoad() {
        super.viewDidLoad()
        PreviewLog.write("viewDidLoad")
        populate()
    }

    private func populate() {
        guard let document, let fileURL else {
            errorTitle.stringValue = "Önizleme üretilemedi"
            errorMessage.stringValue = failureMessage ?? "Bilinmeyen hata."
            errorCard.isHidden = false
            headerCard.isHidden = true
            sheetView.isHidden = true
            summaryCard.isHidden = true
            footerLabel.stringValue = fileURL?.lastPathComponent ?? ""
            return
        }

        errorCard.isHidden = true
        headerCard.isHidden = false
        sheetView.isHidden = false

        titleLabel.stringValue = document.title

        var subtitleParts: [String] = []
        if let court = document.court { subtitleParts.append(court) }
        subtitleParts.append(fileURL.deletingPathExtension().lastPathComponent)
        subtitleLabel.stringValue = subtitleParts.joined(separator: "  •  ")

        // Rozetler
        var badges: [BadgeRowView.Badge] = []
        if !document.formatVersion.isEmpty {
            badges.append(
                BadgeRowView.Badge(
                    text: "UYAP \(document.formatVersion)",
                    fill: NSColor.systemIndigo.withAlphaComponent(0.16),
                    textColor: .systemIndigo
                )
            )
        }
        if document.signature.isSigned {
            badges.append(
                BadgeRowView.Badge(
                    text: "İmzalı",
                    fill: NSColor.systemGreen.withAlphaComponent(0.20),
                    textColor: .systemGreen
                )
            )
        } else {
            badges.append(
                BadgeRowView.Badge(
                    text: "İmzasız",
                    fill: NSColor.tertiaryLabelColor.withAlphaComponent(0.20),
                    textColor: .secondaryLabelColor
                )
            )
        }
        badges.append(
            BadgeRowView.Badge(
                text: "\(document.paragraphCount) ¶",
                fill: NSColor.tertiaryLabelColor.withAlphaComponent(0.20),
                textColor: .secondaryLabelColor
            )
        )
        badgeRow.setBadges(badges)

        // Özet alanları (DAVACI / DAVALI / KONU ...)
        summaryRows.forEach { $0.key.removeFromSuperview(); $0.value.removeFromSuperview() }
        summaryRows.removeAll()

        let fields = document.summaryFields
        summaryCard.isHidden = fields.isEmpty

        for field in fields {
            let key = NSTextField(labelWithString: field.key)
            key.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
            key.textColor = .secondaryLabelColor
            key.lineBreakMode = .byTruncatingTail

            let value = NSTextField(labelWithString: field.value)
            value.font = NSFont.systemFont(ofSize: 11)
            value.textColor = .labelColor
            value.lineBreakMode = .byTruncatingTail
            value.maximumNumberOfLines = 1

            summaryCard.addSubview(key)
            summaryCard.addSubview(value)
            summaryRows.append((key: key, value: value))
        }

        // Belge metni
        textView.textStorage?.setAttributedString(
            UDFTextRenderer.attributedString(for: document.content)
        )

        // Altbilgi
        var footer = [fileURL.lastPathComponent]
        footer.append(ByteCountFormatter.string(fromByteCount: document.fileSize, countStyle: .file))
        if let modified = document.modifiedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            footer.append(formatter.string(from: modified))
        }
        if let signer = document.signature.signerName {
            footer.append(signer)
        }
        footerLabel.stringValue = footer.joined(separator: "  •  ")
    }

    // MARK: Yerleşim

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutContent()
    }

    private func layoutContent() {
        let width = view.bounds.width
        let height = view.bounds.height
        let compact = width < 320
        let headerHeight: CGFloat = compact ? 70 : 92
        let footerHeight: CGFloat = compact ? 18 : 22
        let gap: CGFloat = 10
        let minimumDocumentHeight: CGFloat = compact ? 80 : 120
        var y: CGFloat = 0

        guard document != nil else {
            errorCard.isHidden = false
            headerCard.isHidden = true
            sheetView.isHidden = true
            summaryCard.isHidden = true
            errorCard.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let inset: CGFloat = 14
            errorTitle.frame = NSRect(x: inset, y: inset, width: width - inset * 2, height: 18)
            errorMessage.frame = NSRect(
                x: inset,
                y: inset + 24,
                width: width - inset * 2,
                height: max(40, height - inset * 2 - 24)
            )
            footerLabel.frame = NSRect(x: 0, y: height - 24, width: width, height: 16)
            return
        }

        // Başlık kartı
        headerCard.frame = NSRect(x: 0, y: y, width: width, height: headerHeight)
        layoutHeader(in: headerCard, compact: compact)
        y += headerHeight + gap

        // Altbilgi
        footerLabel.frame = NSRect(x: 0, y: height - footerHeight, width: width, height: 16)

        // Belge sayfası en az yer almalı; yoksa özet kartı gizlenir.
        let availableForContent = height - y - footerHeight - gap
        let summaryRowHeight: CGFloat = compact ? 15 : 18
        let summaryHeight = CGFloat(summaryRows.count) * summaryRowHeight + (compact ? 8 : 12)

        let showSummary = !summaryCard.isHidden
            && availableForContent - summaryHeight - gap >= minimumDocumentHeight

        if showSummary {
            summaryCard.frame = NSRect(x: 0, y: y, width: width, height: summaryHeight)
            layoutSummary(in: summaryCard, rowHeight: summaryRowHeight, compact: compact)
            y += summaryHeight + gap
        } else {
            summaryCard.frame = .zero
        }

        // Belge sayfası
        let sheetHeight = max(minimumDocumentHeight, height - y - footerHeight - gap)
        sheetView.frame = NSRect(x: 0, y: y, width: width, height: sheetHeight)
        scrollView.frame = sheetView.bounds
    }

    private func layoutHeader(in card: NSView, compact: Bool) {
        let inset: CGFloat = 12
        let iconSize: CGFloat = compact ? 30 : 38
        iconView.frame = NSRect(x: inset, y: inset, width: iconSize, height: iconSize)

        let textX = inset + iconSize + 10
        let textWidth = card.bounds.width - textX - inset
        guard textWidth > 20 else { return }

        let titleHeight: CGFloat = compact ? 16 : 18
        titleLabel.frame = NSRect(x: textX, y: inset - 1, width: textWidth, height: titleHeight)
        subtitleLabel.frame = NSRect(x: textX, y: inset + titleHeight + 1, width: textWidth, height: 15)
        badgeRow.frame = NSRect(x: textX, y: inset + titleHeight + 21, width: textWidth, height: 17)
    }

    private func layoutSummary(in card: NSView, rowHeight: CGFloat, compact: Bool) {
        let inset: CGFloat = compact ? 8 : 10
        let keyWidth: CGFloat = compact ? 52 : 62
        var rowY = inset

        for row in summaryRows {
            if compact {
                row.key.frame = NSRect(x: inset, y: rowY, width: keyWidth, height: rowHeight)
                row.value.frame = NSRect(
                    x: inset + keyWidth + 4,
                    y: rowY,
                    width: card.bounds.width - inset * 2 - keyWidth - 4,
                    height: rowHeight
                )
            } else {
                row.key.frame = NSRect(x: inset, y: rowY, width: keyWidth, height: rowHeight)
                row.value.frame = NSRect(
                    x: inset + keyWidth + 6,
                    y: rowY,
                    width: card.bounds.width - inset * 2 - keyWidth - 6,
                    height: rowHeight
                )
            }
            rowY += rowHeight
        }
    }
}
