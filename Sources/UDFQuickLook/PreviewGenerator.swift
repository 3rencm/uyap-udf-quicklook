import Cocoa
import QuickLookUI
import UDFKit

// MARK: - Uygulama delegesi
//
// Bu uygulama iki iş yapar:
//   1) QuickLook Preview Extension'ı kendisi PlugInKit'e kaydeder (kurulum).
//   2) Kullanıcıya bir "hazel mi?" penceresi sunar ve hızlı önizleme açabilir.
//
// Kayıt işlemi kullanıcıdan hiçbir komut istemez: uygulama açıldığında kendisi
// `pluginkit -a` çalıştırır. Böylece kullanıcı uygulamayı /Applications'a
// sürükleyip bir kez açtığında .udf önizlemeleri Finder'da çalışmaya başlar.

@objc(AppDelegate)
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let hintLabel = NSTextField(wrappingLabelWithString: "")
    private let actionButton = NSButton(title: "UYAP .udf dosyası seç ve önizle…", target: nil, action: nil)
    private let closeButton = NSButton(title: "Kapat", target: nil, action: nil)
    private let finderButton = NSButton(title: "Finder'ı Yeniden Başlat", target: nil, action: nil)
    private var registrationSucceeded = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        registerExtension()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: Kurulum (kayıt)

    private func registerExtension() {
        let bundleURL = Bundle.main.bundleURL
        let appexURL = bundleURL.appendingPathComponent("Contents/PlugIns/UDFPreview.appex")

        guard FileManager.default.fileExists(atPath: appexURL.path) else {
            showStatus(
                text: "Kurulum hatası: QuickLook eklentisi bulunamadı.\n\(appexURL.path)",
                isError: true
            )
            return
        }

        setStatus(text: "QuickLook eklentisi kaydediliyor…", isError: false)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = ExtensionRegistrar.register(appexURL: appexURL)
            DispatchQueue.main.async {
                self?.handleRegistrationResult(result, bundleURL: bundleURL)
            }
        }
    }

    private func handleRegistrationResult(_ result: ExtensionRegistrar.Result, bundleURL: URL) {
        registrationSucceeded = result.registered

        if !result.registered {
            showStatus(
                text: "Eklenti kaydedilemedi: \(result.message)",
                isError: true
            )
            finderButton.isHidden = false
        } else if result.staleCleanupNeeded {
            // Önceki kurulumdan kalan bir kayıt bulundu. macOS, Finder'ın belleğinde
            // eski servis adını tuttuğu için Finder'ı yeniden başlatıyoruz;
            // aksi halde "genişletme bulunamadı" hatası görünür.
            showStatus(
                text: "Eski kurulum kaydı temizlendi. Finder yeniden başlatılıyor…",
                isError: false
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                ExtensionRegistrar.restartFinder()
                self?.showStatus(
                    text: "Hazır! .udf belgelerinin önizlemesi artık Finder'da görüntüleniyor.",
                    isError: false
                )
            }
        } else {
            showStatus(
                text: "Hazır! .udf belgelerinin önizlemesi artık Finder'da görüntüleniyor.",
                isError: false
            )
        }

        updateLocationHint(bundleURL: bundleURL)
        startWatchingForMove()
    }

    private func updateLocationHint(bundleURL: URL) {
        let standardLocation = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(bundleURL.lastPathComponent)
        if bundleURL.standardizedFileURL.path == standardLocation.standardizedFileURL.path {
            hintLabel.isHidden = true
        } else {
            hintLabel.stringValue = """
                Uygulamayı /Applications klasörüne taşıyabilirsiniz — taşıdıktan sonra \
                kayıt otomatik olarak yeni konuma geçer.
                """
            hintLabel.isHidden = false
        }
    }

    /// Kullanıcı uygulamayı çalışırken taşırsa kayıt yeni konuma taşınsın.
    private func startWatchingForMove() {
        let originalPath = Bundle.main.bundleURL.standardizedFileURL.path
        let fileManager = FileManager.default

        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            // Uygulama taşındıysa eski yol kaybolur.
            guard !fileManager.fileExists(atPath: originalPath) else { return }

            let movedURL = URL(fileURLWithPath: "/Applications")
                .appendingPathComponent(URL(fileURLWithPath: originalPath).lastPathComponent)
            let movedAppex = movedURL.appendingPathComponent("Contents/PlugIns/UDFPreview.appex")
            guard fileManager.fileExists(atPath: movedAppex.path) else { return }

            let result = ExtensionRegistrar.register(appexURL: movedAppex)
            if result.registered {
                self.registrationSucceeded = true
                self.updateLocationHint(bundleURL: movedURL)
                self.showStatus(
                    text: "Hazır! .udf belgelerinin önizlemesi artık Finder'da görüntüleniyor.",
                    isError: false
                )
            }
            timer.invalidate()
        }
    }

    // MARK: Arayüz

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "UYAP UDF Önizleme"
        window.center()

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil)
        icon.contentTintColor = .systemIndigo
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 44, weight: .light)

        let title = NSTextField(labelWithString: "UYAP UDF Önizleme")
        title.font = NSFont.systemFont(ofSize: 17, weight: .semibold)

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center

        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .systemOrange
        hintLabel.alignment = .center
        hintLabel.isHidden = true

        actionButton.target = self
        actionButton.action = #selector(openDocument)
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .large

        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .large

        finderButton.target = self
        finderButton.action = #selector(restartFinder)
        finderButton.bezelStyle = .rounded
        finderButton.controlSize = .large
        finderButton.isHidden = true

        let buttonRow = NSStackView(views: [actionButton, closeButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = NSLayoutConstraint.Attribute.centerX

        let stack = NSStackView(views: [icon, title, statusLabel, hintLabel, buttonRow, finderButton])
        stack.orientation = .vertical
        stack.alignment = NSLayoutConstraint.Attribute.centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 380),
            statusLabel.widthAnchor.constraint(equalToConstant: 380),
            hintLabel.widthAnchor.constraint(equalToConstant: 380)
        ])

        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setStatus(text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    private func showStatus(text: String, isError: Bool) {
        setStatus(text: text, isError: isError)
    }

    @objc private func closeWindow() {
        NSApp.terminate(nil)
    }

    /// Finder'ı yeniden başlatır. macOS, Finder'ı otomatik olarak açar.
    @objc private func restartFinder() {
        setStatus(text: "Finder yeniden başlatılıyor…", isError: false)
        ExtensionRegistrar.restartFinder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showStatus(
                text: "Hazır! .udf belgelerinin önizlemesi artık Finder'da görüntüleniyor.",
                isError: false
            )
        }
    }

    // MARK: Hızlı önizleme

    @objc private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Önizlenecek UYAP .udf belgesini seçin"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let previewPanel = QuickLookPanelController.shared
        previewPanel.show(url: url)
    }
}

// MARK: - Hızlı önizleme denetleyicisi

/// Hızlı önizleme (Space) penceresini açar. QuickLook Preview Extension'ın
/// kendisi çalıştığı için yalnızca paneli yönetmek yeterlidir.
final class QuickLookPanelController: NSObject, QLPreviewPanelDataSource {

    static let shared = QuickLookPanelController()

    private var itemURL: URL?

    func show(url: URL) {
        itemURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        itemURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> any QLPreviewItem {
        (itemURL as NSURL?) ?? (URL(fileURLWithPath: "/") as NSURL)
    }
}

extension QuickLookPanelController: QLPreviewPanelDelegate {}
