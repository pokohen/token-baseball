// 앱 아이콘을 그린다: "토큰 스포츠" 글자를 부채꼴 모양으로 펼친다.
// 사용법: swift Scripts/make-icon.swift 결과.png   (보통은 Scripts/make-icon.sh가 부른다)
import AppKit
import CoreText

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// 바탕: macOS 아이콘 모양의 둥근 사각형 (가장자리에 여백을 둔다).
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
context.saveGState()
context.addPath(tilePath)
context.clip()
let gradient = CGGradient(
    colorsSpace: space, colors: [color(0x1F8A5B), color(0x0E3B2C)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(
    gradient, start: CGPoint(x: size / 2, y: tile.maxY), end: CGPoint(x: size / 2, y: tile.minY), options: [])

// 부채: 아래쪽 한 점에서 펼쳐지는 살과 테두리.
let pivot = CGPoint(x: size / 2, y: 215)
let spread: CGFloat = 42 * .pi / 180          // 가운데에서 양쪽으로 펼쳐지는 각
let outer: CGFloat = 575
let inner: CGFloat = 150
func point(_ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
    CGPoint(x: pivot.x + radius * sin(angle), y: pivot.y + radius * cos(angle))
}
let fan = CGMutablePath()
fan.move(to: point(inner, -spread))
fan.addLine(to: point(outer, -spread))
fan.addArc(center: pivot, radius: outer, startAngle: .pi / 2 + spread, endAngle: .pi / 2 - spread, clockwise: true)
fan.addLine(to: point(inner, spread))
fan.addArc(center: pivot, radius: inner, startAngle: .pi / 2 - spread, endAngle: .pi / 2 + spread, clockwise: false)
fan.closeSubpath()
context.addPath(fan)
context.setFillColor(color(0xFFF6DC))
context.fillPath()

// 부챗살
context.setStrokeColor(color(0xC9A24A, 0.55))
context.setLineWidth(5)
let ribs = 8
for index in 0...ribs {
    let angle = -spread + spread * 2 * CGFloat(index) / CGFloat(ribs)
    context.move(to: point(inner, angle))
    context.addLine(to: point(outer, angle))
}
context.strokePath()
// 부채 위쪽의 띠
context.setStrokeColor(color(0xE0A526))
context.setLineWidth(22)
context.addArc(center: pivot, radius: outer - 11, startAngle: .pi / 2 + spread, endAngle: .pi / 2 - spread, clockwise: true)
context.strokePath()
// 손잡이
context.setFillColor(color(0xE0A526))
context.addArc(center: pivot, radius: 40, startAngle: 0, endAngle: .pi * 2, clockwise: false)
context.fillPath()
context.setFillColor(color(0x0E3B2C))
context.addArc(center: pivot, radius: 15, startAngle: 0, endAngle: .pi * 2, clockwise: false)
context.fillPath()

// 글자: 윗줄 "토큰", 아랫줄 "스포츠"를 부채의 호를 따라 놓는다.
func drawArc(_ text: String, radius: CGFloat, fontSize: CGFloat, step: CGFloat, fill: CGColor) {
    let heavy = CTFontCreateWithName("AppleSDGothicNeo-Heavy" as CFString, fontSize, nil)
    let letters = Array(text)
    for (index, letter) in letters.enumerated() {
        let angle = (CGFloat(index) - CGFloat(letters.count - 1) / 2) * step
        let attributed = NSAttributedString(string: String(letter), attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): heavy,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): fill,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        context.translateBy(x: pivot.x, y: pivot.y)
        context.rotate(by: -angle)
        context.translateBy(x: 0, y: radius)
        context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
drawArc("토큰", radius: 452, fontSize: 190, step: 27 * .pi / 180, fill: color(0x0E3B2C))
drawArc("스포츠", radius: 275, fontSize: 130, step: 27 * .pi / 180, fill: color(0xB23A2E))
context.restoreGState()

let image = context.makeImage()!
let bitmap = NSBitmapImageRep(cgImage: image)
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
