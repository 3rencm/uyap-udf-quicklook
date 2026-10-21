#!/usr/bin/env swift
//
// Uygulama ikonunu üretir: UYAP belgesi + mühür/rozet motifinden oluşan,
// yuvarlatılmış köşeli degrade bir simge.
//
// Kullanım: swift Tools/makeicon.swift <çıktı.icns>

import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let masterSize: CGFloat = 1024

// MARK: - Çizim

func makeImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.06
    let body = rect.insetBy(dx: inset, dy: inset)
    let radius = size * 0.22

    // Arka plan degradesi
    let background = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.33, green: 0.36, blue: 0.78, alpha: 1),
        NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.55, alpha: 1)
    ])
    gradient?.draw(in: background, angle: -90)

    // Belge kâğıdı
    let pageWidth = body.width * 0.50
    let pageHeight = body.height * 0.62
    let page = NSRect(
        x: body.midX - pageWidth / 2 - body.width * 0.03,
        y: body.midY - pageHeight / 2,
        width: pageWidth,
        height: pageHeight
    )
    let pagePath = NSBezierPath(roundedRect: page, xRadius: size * 0.035, yRadius: size * 0.035)
    NSColor.white.withAlphaComponent(0.96).setFill()
    pagePath.fill()

    // Satırlar
    NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
    for index in 0..<6 {
        let lineY = page.maxY - page.height * 0.18 - CGFloat(index) * page.height * 0.11
        let insetRatio = index == 0 ? 0.10 : 0.06
        let line = NSBezierPath()
        line.lineWidth = max(1, size * 0.018)
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: page.minX + page.width * insetRatio, y: lineY))
        line.line(to: NSPoint(x: page.maxX - page.width * insetRatio, y: lineY))
        line.stroke()
    }

    // Mühür rozeti
    let badgeSize = body.width * 0.34
    let badge = NSRect(
        x: body.maxX - badgeSize * 0.78,
        y: body.minY + badgeSize * 0.10,
        width: badgeSize,
        height: badgeSize
    )
    let badgePath = NSBezierPath(ovalIn: badge)
    NSColor(calibratedRed: 0.85, green: 0.20, blue: 0.24, alpha: 1).setFill()
    badgePath.fill()

    // Onay işareti
    let check = NSBezierPath()
    check.lineWidth = max(2, size * 0.035)
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.move(to: NSPoint(x: badge.minX + badge.width * 0.26, y: badge.midY + badge.height * 0.02))
    check.line(to: NSPoint(x: badge.minX + badge.width * 0.44, y: badge.minY + badge.height * 0.24))
    check.line(to: NSPoint(x: badge.minX + badge.width * 0.76, y: badge.maxY - badge.height * 0.26))
    NSColor.white.setStroke()
    check.stroke()

    image.unlockFocus()
    return image
}

// MARK: - PNG dışa aktarma

func logError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func pngData(from image: NSImage, size: CGFloat) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let resized = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size),
            pixelsHigh: Int(size),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
          ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    image.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    return resized.representation(using: .png, properties: [:])
}

// MARK: - iconset üretimi

let master = makeImage(size: masterSize)
let temporaryDirectory = NSTemporaryDirectory() + "UDFQuickLookIcon-\(UUID().uuidString)"
let iconsetPath = temporaryDirectory + ".iconset"

try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

struct Variant {
    let name: String
    let pixels: CGFloat
    let scale: Int
}

let variants: [Variant] = [
    Variant(name: "icon_16x16", pixels: 16, scale: 1),
    Variant(name: "icon_16x16", pixels: 32, scale: 2),
    Variant(name: "icon_32x32", pixels: 32, scale: 1),
    Variant(name: "icon_32x32", pixels: 64, scale: 2),
    Variant(name: "icon_128x128", pixels: 128, scale: 1),
    Variant(name: "icon_128x128", pixels: 256, scale: 2),
    Variant(name: "icon_256x256", pixels: 256, scale: 1),
    Variant(name: "icon_256x256", pixels: 512, scale: 2),
    Variant(name: "icon_512x512", pixels: 512, scale: 1),
    Variant(name: "icon_512x512", pixels: 1024, scale: 2),
    Variant(name: "icon_1024x1024", pixels: 1024, scale: 1)
]

for variant in variants {
    let filename = variant.scale == 2
        ? "\(variant.name)@2x.png"
        : "\(variant.name).png"
    let scaled = makeImage(size: variant.pixels)
    guard let data = pngData(from: scaled, size: variant.pixels) else { continue }
    try? data.write(to: URL(fileURLWithPath: iconsetPath + "/" + filename))
}

// MARK: - iconutil

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", outputPath]
process.standardOutput = FileHandle.nullDevice
process.standardError = FileHandle.nullDevice

do {
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus == 0 {
        print("İkon üretildi: \(outputPath)")
    } else {
        logError("iconutil başarısız oldu (status \(process.terminationStatus)).")
    }
} catch {
    logError("iconutil çalıştırılamadı: \(error)")
}

try? FileManager.default.removeItem(atPath: iconsetPath)
try? FileManager.default.removeItem(atPath: temporaryDirectory)
