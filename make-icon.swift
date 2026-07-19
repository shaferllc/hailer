#!/usr/bin/env swift
// Generates AppIcon.icns: a brass loud-hailer (speaking trumpet) on a
// deep-sea blue squircle, drawn programmatically with AppKit.
// Usage: swift make-icon.swift  (run from the hailer dir)

import AppKit
import Foundation

let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = here.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func makePNG(size px: Int) -> Data? {
    let pf = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)
    else { return nil }
    rep.size = NSSize(width: pf, height: pf)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx

    // Squircle background: azure over deep-sea navy.
    let radius = pf * 0.225
    let squircle = NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: pf, height: pf),
        xRadius: radius, yRadius: radius)
    squircle.addClip()
    let grad = NSGradient(colors: [
        NSColor(red: 0.05, green: 0.42, blue: 0.68, alpha: 1),
        NSColor(red: 0.02, green: 0.12, blue: 0.31, alpha: 1),
    ])!
    grad.draw(in: NSRect(x: 0, y: 0, width: pf, height: pf), angle: -90)

    // The loud-hailer, built around the origin then tilted up and centered.
    let brass = NSColor(red: 0.99, green: 0.78, blue: 0.28, alpha: 1)
    let mx = -pf * 0.27           // mouthpiece x
    let bx = pf * 0.10            // bell x
    let mr = pf * 0.05            // mouth half-height
    let br = pf * 0.16            // bell half-height

    var brassPaths: [NSBezierPath] = []

    // Cone.
    let cone = NSBezierPath()
    cone.move(to: NSPoint(x: mx, y: -mr))
    cone.line(to: NSPoint(x: bx, y: -br))
    cone.line(to: NSPoint(x: bx, y: br))
    cone.line(to: NSPoint(x: mx, y: mr))
    cone.close()
    brassPaths.append(cone)

    // Flared bell lip.
    let lipW = pf * 0.05
    brassPaths.append(NSBezierPath(
        roundedRect: NSRect(x: bx - lipW * 0.25, y: -br * 1.2, width: lipW, height: br * 2.4),
        xRadius: lipW / 2, yRadius: lipW / 2))

    // Mouthpiece cap.
    let capR = pf * 0.055
    brassPaths.append(NSBezierPath(
        ovalIn: NSRect(x: mx - capR * 1.2, y: -capR, width: capR * 2, height: capR * 2)))

    // Handle hanging under the cone.
    let hw = pf * 0.05
    brassPaths.append(NSBezierPath(
        roundedRect: NSRect(x: mx + pf * 0.05, y: -pf * 0.21, width: hw, height: pf * 0.17),
        xRadius: hw / 2, yRadius: hw / 2))

    // Sound arcs hailing out of the bell.
    var arcPaths: [NSBezierPath] = []
    let arcCenter = NSPoint(x: bx + pf * 0.05, y: 0)
    for r in [pf * 0.12, pf * 0.19, pf * 0.26] {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: arcCenter, radius: r, startAngle: -32, endAngle: 32)
        arc.lineWidth = max(1, pf * 0.03)
        arc.lineCapStyle = .round
        arcPaths.append(arc)
    }

    // Tilt the whole glyph up 14° and move it to the icon center.
    let rotate = AffineTransform(rotationByDegrees: 14)
    let translate = AffineTransform(translationByX: pf * 0.47, byY: pf * 0.48)
    for path in brassPaths + arcPaths {
        path.transform(using: rotate)
        path.transform(using: translate)
    }

    brass.setFill()
    for path in brassPaths {
        path.lineJoinStyle = .round
        path.fill()
    }

    NSColor(white: 1, alpha: 0.92).setStroke()
    for arc in arcPaths {
        arc.stroke()
    }

    return rep.representation(using: .png, properties: [:])
}

for (name, px) in sizes {
    guard let data = makePNG(size: px) else { continue }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path,
                  "-o", here.appendingPathComponent("AppIcon.icns").path]
try proc.run()
proc.waitUntilExit()
print("Wrote AppIcon.icns")
