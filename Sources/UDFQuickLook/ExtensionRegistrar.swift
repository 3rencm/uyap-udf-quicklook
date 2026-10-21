import Foundation

// MARK: - QuickLook eklentisinin kendini kaydetmesi
//
// macOS'ta Preview Extension'lar PlugInKit veritabanına elle eklenmek zorundadır.
// Bu işi kullanıcıdan terminal komutu beklemeden uygulamanın kendisi yapar:
// açılışta `pluginkit -a` çalıştırılır ve sonuç doğrulanır.
//
// Bu, uygulamanın sandbox'lanmamış olmasını gerektirir; sandbox'lanan bir süreç
// pkd (com.apple.pluginkit.pkd) ile konuşamaz.
//
// ÖNEMLİ: Bundle kimliği değişirse (örneğin "com.ecmeyva" -> "com.3rencm"),
// macOS'un istemcileri (Finder) eski servis adına ait bağlantıyı bellekte
// tutmaya devam eder ve "genişletme bulunamadı" hatası verir. Bu yüzden eski
// kayıtlar temizlenir ve "staleCleanupNeeded" bilgisi döndürülür; uygulama
// bu durumda kullanıcıya Finder'ı yeniden başlatma seçeneği sunar.

enum ExtensionRegistrar {

    static let pluginIdentifier = "com.3rencm.udfquicklook.preview"

    /// Önceki sürümlerden kalan kimlikler. Yeni sürüm kurulduğunda temizlenir.
    static let legacyPluginIdentifiers = [
        "com.ecmeyva.udfquicklook.preview"
    ]

    struct Result {
        let registered: Bool
        let message: String
        /// Eski (bayat) kayıtlar temizlendiyse Finder'ın belleğinde eski
        /// bağlantı kalabilir; Finder yeniden başlatılmalıdır.
        let staleCleanupNeeded: Bool
    }

    // MARK: Kayıt

    /// Eklentiyi PlugInKit'e kaydeder. Uygulamanın içinde bulunduğu appex yolunu kullanır.
    @discardableResult
    static func register(appexURL: URL) -> Result {
        let currentPath = appexURL.path

        // 1) Uygulama taşınmışsa eski yol kaydı geçersizdir.
        // 2) Bundle kimliği değişmişse eski kimlikle kayıtlı eklentiler geçersizdir.
        let staleCleanupNeeded = cleanStaleRegistrations(currentPath: currentPath)

        // 3) Kaydı ekle.
        let addResult = run(arguments: ["-a", currentPath])

        guard registeredPaths().contains(currentPath) else {
            let detail = addResult.output.isEmpty
                ? "pluginkit komutu başarısız oldu (kod \(addResult.status))."
                : addResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return Result(registered: false, message: detail, staleCleanupNeeded: staleCleanupNeeded)
        }

        // QuickLook servisleri (QuickLookUIService) eklenti listesini açılışta alır;
        // kayıt sonrası yenilemek gerekir.
        resetQuickLookServices()

        return Result(
            registered: true,
            message: "Eklenti kaydedildi.",
            staleCleanupNeeded: staleCleanupNeeded
        )
    }

    // MARK: Bayat kayıt temizliği

    private struct Registration {
        let identifier: String
        let path: String
    }

    /// Bu uygulamaya ait eski kayıtları (eski yol, eski bundle kimliği) kaldırır.
    /// @return Temizlenen bayat kayıt varsa true.
    private static func cleanStaleRegistrations(currentPath: String) -> Bool {
        var cleaned = false

        for registration in allRegistrations() {
            let isCurrent = registration.identifier == pluginIdentifier
                && registration.path == currentPath
            guard !isCurrent else { continue }

            // Sadece bu uygulamaya ait kayıtlara dokun.
            guard registration.identifier.contains("udfquicklook") else { continue }

            cleaned = true
            if registration.path.hasPrefix("/") {
                _ = run(arguments: ["-r", registration.path])
            }
            _ = run(arguments: ["-e", "ignore", "-i", registration.identifier])
        }

        // Listede görünmese de bellekte kalmış olabilen eski kimlikler.
        for legacy in legacyPluginIdentifiers {
            _ = run(arguments: ["-e", "ignore", "-i", legacy])
        }

        return cleaned
    }

    /// PlugInKit veritabanındaki tüm kayıtları okur.
    private static func allRegistrations() -> [Registration] {
        let output = run(arguments: ["-m", "-A", "-D", "-v"]).output
        var registrations: [Registration] = []

        for line in output.split(separator: "\n") {
            let fields = line
                .split(separator: "\t", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2, let path = fields.last, path.hasPrefix("/") else { continue }

            var identifier = fields[0]
            if identifier.hasPrefix("+") || identifier.hasPrefix("-") {
                identifier.removeFirst()
            }
            if let paren = identifier.range(of: "(") {
                identifier = String(identifier[..<paren.lowerBound])
            }
            guard identifier.contains(".") else { continue }

            registrations.append(Registration(identifier: identifier, path: path))
        }

        return registrations
    }

    /// PlugInKit veritabanında kayıtlı olan eklenti yolları (yalnızca güncel kimlik).
    private static func registeredPaths() -> [String] {
        let output = run(arguments: ["-m", "-A", "-D", "-v", "-i", pluginIdentifier]).output
        return output
            .split(separator: "\n")
            .compactMap { line -> String? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard let last = fields.last else { return nil }
                let path = last.trimmingCharacters(in: .whitespaces)
                return path.hasPrefix("/") ? path : nil
            }
    }

    // MARK: QuickLook servislerini yenileme

    /// QuickLook sunucusunu ve önbelleğini yeniler.
    static func resetQuickLookServices() {
        _ = run(arguments: ["-r"], tool: "/usr/bin/qlmanage")
        _ = run(arguments: ["-r", "cache"], tool: "/usr/bin/qlmanage")
    }

    // MARK: Finder yeniden başlatma

    /// Finder'ı yeniden başlatır (açık dosya pencereleri kapanır, Finder geri gelir).
    /// macOS, Finder'ı otomatik olarak yeniden başlatır.
    static func restartFinder() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: Komut çalıştırma

    @discardableResult
    private static func run(arguments: [String], tool: String = "/usr/bin/pluginkit") -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, text)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
