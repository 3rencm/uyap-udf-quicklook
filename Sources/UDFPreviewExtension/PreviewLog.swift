import Foundation

/// Eklenti sürecinde teşhis amaçlı günlük yazıcı.
/// Sandbox, unified log'un bazı ortamlarda görünmemesine yol açabildiği için
/// mesajlar aynı zamanda eklenti konteynerindeki bir dosyaya da yazılır.
enum PreviewLog {
    private static let lock = NSLock()

    static var fileURL: URL? {
        // Sandbox içinde bu yol eklenti konteynerine işaret eder.
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("udfpreview.log")
    }

    static func write(_ message: String) {
        NSLog("[UDFPreview] %@", message)

        lock.lock()
        defer { lock.unlock() }

        guard let fileURL else { return }
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
