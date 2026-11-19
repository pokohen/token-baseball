// 앱 아이콘을 그린다: macOS 아이콘 모양의 둥근 사각형 위에 로고(Resources/AppLogo.png)를 올린다.
// 사용법: swift Scripts/make-icon.swift 로고.png 결과.png   (보통은 Scripts/make-icon.sh가 부른다)
//
// 로고는 배경이 투명한 PNG여야 한다. 받은 그림의 배경이 투명이 아니면(체크무늬가 그림으로 들어가 있는 경우 등)
// 먼저 배경을 지워서 넣는다.
import AppKit

let size: CGFloat = 1024
let arguments = CommandLine.arguments
guard arguments.count > 2,
      let source = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("사용법: swift Scripts/make-icon.swift 로고.png 결과.png\n".utf8))
    exit(1)
}

let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// 바탕: 가장자리에 여백을 둔 둥근 사각형. 로고의 노란 테두리가 잘 보이게 짙은 남색으로 깐다.
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
context.saveGState()
context.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
context.clip()
let gradient = CGGradient(colorsSpace: space, colors: [color(0x26304A), color(0x101422)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(
    gradient, start: CGPoint(x: size / 2, y: tile.maxY), end: CGPoint(x: size / 2, y: tile.minY), options: [])
context.restoreGState()

// 로고: 긴 쪽이 700이 되게 줄여 가운데에 놓는다. 도트 그림이지만 크기가 딱 떨어지지 않아 부드럽게 줄인다.
let side: CGFloat = 700
let scale = side / CGFloat(max(source.width, source.height))
let width = CGFloat(source.width) * scale, height = CGFloat(source.height) * scale
context.interpolationQuality = .high
context.draw(source, in: CGRect(x: (size - width) / 2, y: (size - height) / 2, width: width, height: height))

let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
