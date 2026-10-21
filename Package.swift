// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UDFQuickLook",
    platforms: [.macOS(.v13)],
    targets: [
        // Ortak kod: ZIP okuyucu, UDF ayrıştırıcı, imza okuyucu, metin biçimlendirici
        .target(
            name: "UDFKit",
            path: "Sources/UDFKit"
        ),
        // Preview Extension (com.apple.quicklook.preview) -> Finder önizleme paneli
        //
        // Uygulama eklentileri Xcode'da giriş noktası olarak _NSExtensionMain ile
        // bağlanır; bu olmadan eklenti sistemi isteği eklentiye iletemez.
        .executableTarget(
            name: "UDFPreviewExtension",
            dependencies: ["UDFKit"],
            path: "Sources/UDFPreviewExtension",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
        ),
        // Komut satırı inceleme aracı (sandbox'sız)
        .executableTarget(
            name: "UDFInspect",
            dependencies: ["UDFKit"],
            path: "Sources/UDFInspect"
        ),
        // Ana uygulama (extension barındırıcısı)
        .executableTarget(
            name: "UDFQuickLook",
            dependencies: ["UDFKit"],
            path: "Sources/UDFQuickLook"
        )
    ]
)
