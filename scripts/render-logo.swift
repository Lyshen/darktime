import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "assets/darktime-logo.png"
let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Unable to create bitmap context.")
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255
    let green = CGFloat((hex >> 8) & 0xff) / 255
    let blue = CGFloat(hex & 0xff) / 255
    return CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawLine(_ points: [CGPoint], color lineColor: CGColor, width: CGFloat) {
    guard let first = points.first else {
        return
    }
    let path = CGMutablePath()
    path.move(to: first)
    for point in points.dropFirst() {
        path.addLine(to: point)
    }
    context.addPath(path)
    context.setStrokeColor(lineColor)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.strokePath()
}

context.clear(CGRect(x: 0, y: 0, width: size, height: size))
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)

let iconRect = CGRect(x: 64, y: 64, width: 896, height: 896)
let iconPath = roundedRect(iconRect, 224)

context.saveGState()
context.addPath(iconPath)
context.clip()
context.drawLinearGradient(
    gradient([color(0x151B24), color(0x070A0F), color(0x10161D)], [0, 0.48, 1]),
    start: CGPoint(x: 128, y: 96),
    end: CGPoint(x: 896, y: 928),
    options: []
)
context.drawRadialGradient(
    gradient([color(0x2FE7D0, 0.5), color(0x1A7480, 0.18), color(0x000000, 0)], [0, 0.46, 1]),
    startCenter: CGPoint(x: 676, y: 296),
    startRadius: 8,
    endCenter: CGPoint(x: 676, y: 296),
    endRadius: 560,
    options: [.drawsAfterEndLocation]
)
context.restoreGState()

context.addPath(roundedRect(CGRect(x: 83, y: 83, width: 858, height: 858), 205))
context.setStrokeColor(color(0xFFFFFF, 0.08))
context.setLineWidth(38)
context.strokePath()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: 26), blur: 32, color: color(0x000000, 0.45))

let dPath = CGMutablePath()
dPath.move(to: CGPoint(x: 342, y: 236))
dPath.addLine(to: CGPoint(x: 504, y: 236))
dPath.addCurve(to: CGPoint(x: 788, y: 512), control1: CGPoint(x: 661, y: 236), control2: CGPoint(x: 788, y: 357))
dPath.addCurve(to: CGPoint(x: 504, y: 788), control1: CGPoint(x: 788, y: 667), control2: CGPoint(x: 661, y: 788))
dPath.addLine(to: CGPoint(x: 342, y: 788))
dPath.addCurve(to: CGPoint(x: 285, y: 731), control1: CGPoint(x: 310.5, y: 788), control2: CGPoint(x: 285, y: 762.5))
dPath.addLine(to: CGPoint(x: 285, y: 293))
dPath.addCurve(to: CGPoint(x: 342, y: 236), control1: CGPoint(x: 285, y: 261.5), control2: CGPoint(x: 310.5, y: 236))
dPath.closeSubpath()

let holePath = CGMutablePath()
holePath.move(to: CGPoint(x: 397, y: 334))
holePath.addLine(to: CGPoint(x: 504, y: 334))
holePath.addCurve(to: CGPoint(x: 686, y: 512), control1: CGPoint(x: 604.5, y: 334), control2: CGPoint(x: 686, y: 412))
holePath.addCurve(to: CGPoint(x: 504, y: 690), control1: CGPoint(x: 686, y: 612), control2: CGPoint(x: 604.5, y: 690))
holePath.addLine(to: CGPoint(x: 397, y: 690))
holePath.closeSubpath()

dPath.addPath(holePath)
context.addPath(dPath)
context.clip(using: .evenOdd)
context.drawLinearGradient(
    gradient([color(0xD7FFF8), color(0x40E3D0), color(0x1B7A8C)], [0, 0.46, 1]),
    start: CGPoint(x: 317, y: 256),
    end: CGPoint(x: 706, y: 770),
    options: []
)
context.restoreGState()

let innerPath = CGMutablePath()
innerPath.move(to: CGPoint(x: 454, y: 393))
innerPath.addLine(to: CGPoint(x: 500, y: 393))
innerPath.addCurve(to: CGPoint(x: 627, y: 512), control1: CGPoint(x: 570, y: 393), control2: CGPoint(x: 627, y: 446.5))
innerPath.addCurve(to: CGPoint(x: 500, y: 631), control1: CGPoint(x: 627, y: 577.5), control2: CGPoint(x: 570, y: 631))
innerPath.addLine(to: CGPoint(x: 454, y: 631))
innerPath.closeSubpath()
context.addPath(innerPath)
context.setFillColor(color(0x080B10))
context.fillPath()

let crescent = CGMutablePath()
crescent.move(to: CGPoint(x: 429, y: 392))
crescent.addLine(to: CGPoint(x: 504, y: 392))
crescent.addCurve(to: CGPoint(x: 398, y: 560), control1: CGPoint(x: 435.5, y: 426.5), control2: CGPoint(x: 392.5, y: 491))
crescent.addCurve(to: CGPoint(x: 445, y: 661), control1: CGPoint(x: 401, y: 599), control2: CGPoint(x: 419, y: 634))
crescent.addLine(to: CGPoint(x: 397, y: 661))
crescent.addLine(to: CGPoint(x: 397, y: 438))
crescent.addCurve(to: CGPoint(x: 429, y: 392), control1: CGPoint(x: 397, y: 413), control2: CGPoint(x: 404, y: 392))
crescent.closeSubpath()
context.addPath(crescent)
context.setFillColor(color(0x0F151D, 0.92))
context.fillPath()

drawLine([CGPoint(x: 383, y: 304), CGPoint(x: 515, y: 304)], color: color(0xE9FFFB, 0.92), width: 34)
drawLine([CGPoint(x: 383, y: 720), CGPoint(x: 515, y: 720)], color: color(0xE9FFFB, 0.72), width: 34)

context.saveGState()
let warmPath = CGMutablePath()
warmPath.move(to: CGPoint(x: 641, y: 334))
warmPath.addCurve(to: CGPoint(x: 731, y: 448), control1: CGPoint(x: 684, y: 360), control2: CGPoint(x: 716, y: 401))
context.addPath(warmPath)
context.replacePathWithStrokedPath()
context.clip()
context.drawLinearGradient(
    gradient([color(0xFFE6A3), color(0xF1A545)], [0, 1]),
    start: CGPoint(x: 641, y: 275),
    end: CGPoint(x: 759, y: 467),
    options: []
)
context.restoreGState()

context.saveGState()
context.addEllipse(in: CGRect(x: 676, y: 284, width: 76, height: 76))
context.clip()
context.drawLinearGradient(
    gradient([color(0xFFE6A3), color(0xF1A545)], [0, 1]),
    start: CGPoint(x: 676, y: 284),
    end: CGPoint(x: 752, y: 360),
    options: []
)
context.restoreGState()

context.addPath(roundedRect(CGRect(x: 303, y: 777, width: 418, height: 20), 10))
context.setFillColor(color(0xFFFFFF, 0.12))
context.fillPath()
context.addPath(roundedRect(CGRect(x: 303, y: 777, width: 202, height: 20), 10))
context.setFillColor(color(0x37D9C8, 0.42))
context.fillPath()

guard let image = context.makeImage() else {
    fatalError("Unable to create image.")
}

let bitmap = NSBitmapImageRep(cgImage: image)
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode PNG.")
}

let url = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: url)
