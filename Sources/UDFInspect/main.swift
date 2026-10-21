import Cocoa
import UDFKit

// UYAP .udf belgesini arayüz açmadan inceler ve içeriği terminale yazar.
//
//   udf-inspect /path/to/belge.udf
//
// Bu araç sandbox'lanmamıştır; bu sayede komut satırından herhangi bir dosya
// okunabilir. QuickLook eklentisinin doğru çalıştığını doğrulamak ve belge
// içeriğini hızlıca görmek için kullanılır.

if CommandLine.arguments.count > 1, CommandLine.arguments[1] != "--help" {
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    do {
        let document = try UDFDocument.load(url: url)
        print("Dosya            : \(url.lastPathComponent)")
        print("Boyut            : \(document.fileSize) bayt")
        print("Format sürümü    : \(document.formatVersion)")
        print("Başlık           : \(document.title)")
        print("Mahkeme          : \(document.court ?? "-")")
        print("Paragraf         : \(document.paragraphCount)")
        print("Karakter         : \(document.characterCount)")
        print("Kelime           : \(document.wordCount)")
        print("Arşiv girdileri  : \(document.archiveEntries.joined(separator: ", "))")
        print("İmza             : \(document.signature.isSigned ? "var" : "yok")")
        print("  İmzalayan      : \(document.signature.signerName ?? "-")")
        print("  Zincir kökü    : \(document.signature.issuerName ?? "-")")
        print("  İmza zamanı    : \(document.signature.signedAt ?? "-")")
        let attributed = UDFTextRenderer.attributedString(for: document.content)
        var fontNames = Set<String>()
        attributed.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            if let font = value as? NSFont { fontNames.insert(font.fontName) }
        }
        print("Yazı tipleri     : \(fontNames.sorted().joined(separator: ", "))")
        print("Özet alanları    :")
        for field in document.summaryFields {
            print("  \(field.key): \(field.value)")
        }
        print("")
        print("--- Belge metni (ilk 1200 karakter) ---")
        print(String(document.plainText.prefix(1200)))
        exit(0)
    } catch {
        print("Hata: \(error.localizedDescription)")
        exit(1)
    }
}

print("Kullanım: udf-inspect /path/to/belge.udf")
exit(2)
