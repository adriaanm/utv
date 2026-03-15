#!/usr/bin/swift
// Generates app icon PNGs for macOS and tvOS targets.
// Red rounded-rect with white uppercase U in the center.

import AppKit

func createContext(width: Int, height: Int) -> CGContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    return CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func savePNG(_ ctx: CGContext, to path: String) {
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("  Created \(path)")
}

let red = CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
let darkRed = CGColor(red: 0.7, green: 0.0, blue: 0.0, alpha: 1.0)
let white = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)

func drawRedRoundedRect(_ ctx: CGContext, width: Int, height: Int, cornerFraction: CGFloat = 0.15) {
    let w = CGFloat(width), h = CGFloat(height)
    let r = min(w, h) * cornerFraction
    let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                      cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.setFillColor(red)
    ctx.addPath(path)
    ctx.fillPath()
}

func drawText(_ ctx: CGContext, text: String, width: Int, height: Int, fontSize: CGFloat) {
    let w = CGFloat(width), h = CGFloat(height)
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: white
    ]
    let str = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
    let line = CTLineCreateWithAttributedString(str)
    let bounds = CTLineGetBoundsWithOptions(line, [])
    let x = (w - bounds.width) / 2 - bounds.origin.x
    let y = (h - bounds.height) / 2 - bounds.origin.y
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

func generateFullIcon(width: Int, height: Int, path: String) {
    let ctx = createContext(width: width, height: height)
    drawRedRoundedRect(ctx, width: width, height: height)
    drawText(ctx, text: "U", width: width, height: height, fontSize: CGFloat(min(width, height)) * 0.6)
    savePNG(ctx, to: path)
}

func generateBackLayer(width: Int, height: Int, path: String) {
    let ctx = createContext(width: width, height: height)
    // Solid darker red fill for parallax depth
    ctx.setFillColor(darkRed)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    savePNG(ctx, to: path)
}

func generateFrontLayer(width: Int, height: Int, path: String) {
    // Front layer must be fully opaque — tvOS handles icon shape masking
    let ctx = createContext(width: width, height: height)
    ctx.setFillColor(red)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    drawText(ctx, text: "U", width: width, height: height, fontSize: CGFloat(min(width, height)) * 0.55)
    savePNG(ctx, to: path)
}

func generateTopShelf(width: Int, height: Int, path: String) {
    let ctx = createContext(width: width, height: height)
    ctx.setFillColor(red)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    drawText(ctx, text: "utv", width: width, height: height, fontSize: CGFloat(height) * 0.4)
    savePNG(ctx, to: path)
}

// --- Setup ---
let base = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "utv/utv"
let fm = FileManager.default
func mkdir(_ p: String) { try? fm.createDirectory(atPath: p, withIntermediateDirectories: true) }

func writeJSON(_ json: String, to path: String) {
    try! json.write(toFile: path, atomically: true, encoding: .utf8)
}

// === macOS Icon ===
print("Generating macOS icon...")
let macDir = "\(base)/Assets.xcassets/AppIcon.appiconset"
mkdir(macDir)
generateFullIcon(width: 512, height: 512, path: "\(macDir)/icon_512.png")
generateFullIcon(width: 1024, height: 1024, path: "\(macDir)/icon_1024.png")
writeJSON("""
{
  "images": [
    { "filename": "icon_512.png", "idiom": "mac", "scale": "1x", "size": "512x512" },
    { "filename": "icon_1024.png", "idiom": "mac", "scale": "2x", "size": "512x512" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
""", to: "\(macDir)/Contents.json")

writeJSON("""
{ "info": { "author": "xcode", "version": 1 } }
""", to: "\(base)/Assets.xcassets/Contents.json")

// === tvOS Brand Assets ===
print("Generating tvOS brand assets...")
let brand = "\(base)/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
mkdir(brand)
writeJSON("""
{
  "assets": [
    { "filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768" },
    { "filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240" },
    { "filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720" },
    { "filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
""", to: "\(brand)/Contents.json")

func createImageStack(dir: String, width: Int, height: Int) {
    mkdir(dir)
    writeJSON("""
    { "layers": [{ "filename": "Back.imagestacklayer" }, { "filename": "Front.imagestacklayer" }], "info": { "author": "xcode", "version": 1 } }
    """, to: "\(dir)/Contents.json")

    for (layer, gen): (String, (Int, Int, String) -> Void) in [("Back", generateBackLayer), ("Front", generateFrontLayer)] {
        let layerDir = "\(dir)/\(layer).imagestacklayer"
        mkdir(layerDir)
        writeJSON("""
        { "info": { "author": "xcode", "version": 1 } }
        """, to: "\(layerDir)/Contents.json")

        let imgDir = "\(layerDir)/Content.imageset"
        mkdir(imgDir)
        let filename = "\(layer.lowercased()).png"
        gen(width, height, "\(imgDir)/\(filename)")
        writeJSON("""
        { "images": [{ "filename": "\(filename)", "idiom": "tv", "scale": "1x" }], "info": { "author": "xcode", "version": 1 } }
        """, to: "\(imgDir)/Contents.json")
    }
}

createImageStack(dir: "\(brand)/App Icon - App Store.imagestack", width: 1280, height: 768)
createImageStack(dir: "\(brand)/App Icon.imagestack", width: 400, height: 240)

for (name, w, h) in [("Top Shelf Image", 1920, 720), ("Top Shelf Image Wide", 2320, 720)] {
    let dir = "\(brand)/\(name).imageset"
    mkdir(dir)
    generateTopShelf(width: w, height: h, path: "\(dir)/shelf.png")
    writeJSON("""
    { "images": [{ "filename": "shelf.png", "idiom": "tv", "scale": "1x" }], "info": { "author": "xcode", "version": 1 } }
    """, to: "\(dir)/Contents.json")
}

print("Done! All icon assets generated.")
