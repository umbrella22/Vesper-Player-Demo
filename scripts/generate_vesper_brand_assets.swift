#!/usr/bin/env swift

import AppKit
import CoreGraphics
import CoreText
import Foundation

private let graphite = CGColor(
  colorSpace: CGColorSpaceCreateDeviceRGB(),
  components: [17 / 255, 19 / 255, 24 / 255, 1]
)!
private let white = CGColor(
  colorSpace: CGColorSpaceCreateDeviceRGB(),
  components: [1, 1, 1, 1]
)!

private func makeContext(width: Int, height: Int, transparent: Bool) -> CGContext {
  let alphaInfo: CGImageAlphaInfo = transparent ? .premultipliedLast : .noneSkipLast
  return CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: alphaInfo.rawValue
  )!
}

private func writePng(
  path: String,
  width: Int,
  height: Int,
  transparent: Bool = false,
  draw: (CGContext) -> Void
) throws {
  let context = makeContext(width: width, height: height, transparent: transparent)
  if transparent {
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
  }
  draw(context)
  let representation = NSBitmapImageRep(cgImage: context.makeImage()!)
  let data = representation.representation(using: .png, properties: [:])!
  try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private func drawMark(
  in context: CGContext,
  center: CGPoint,
  size: CGFloat,
  backgroundColor: CGColor = white,
  playColor: CGColor = graphite
) {
  let rect = CGRect(
    x: center.x - size / 2,
    y: center.y - size / 2,
    width: size,
    height: size
  )
  let mark = CGPath(
    roundedRect: rect,
    cornerWidth: size * 0.22,
    cornerHeight: size * 0.22,
    transform: nil
  )
  context.addPath(mark)
  context.setFillColor(backgroundColor)
  context.fillPath()

  let triangleHeight = size * 0.42
  let triangleWidth = size * 0.34
  let triangleCenterX = center.x + size * 0.035
  let triangle = CGMutablePath()
  triangle.move(
    to: CGPoint(x: triangleCenterX - triangleWidth / 2, y: center.y - triangleHeight / 2)
  )
  triangle.addLine(to: CGPoint(x: triangleCenterX + triangleWidth / 2, y: center.y))
  triangle.addLine(
    to: CGPoint(x: triangleCenterX - triangleWidth / 2, y: center.y + triangleHeight / 2)
  )
  triangle.closeSubpath()
  context.addPath(triangle)
  context.setFillColor(playColor)
  context.fillPath()
}

private func drawIcon(in context: CGContext, width: Int, height: Int) {
  context.setFillColor(graphite)
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  drawMark(
    in: context,
    center: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2),
    size: CGFloat(min(width, height)) * 0.5
  )
}

private func drawWordmark(in context: CGContext, at point: CGPoint) {
  let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 34, nil)
  let attributes: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): white,
    .kern: 1.2,
  ]
  let line = CTLineCreateWithAttributedString(
    NSAttributedString(string: "VESPER", attributes: attributes)
  )
  context.textPosition = point
  CTLineDraw(line, context)
}

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

private let androidLegacySizes: [(String, Int)] = [
  ("mipmap-mdpi", 48),
  ("mipmap-hdpi", 72),
  ("mipmap-xhdpi", 96),
  ("mipmap-xxhdpi", 144),
  ("mipmap-xxxhdpi", 192),
]

private let androidForegroundSizes: [(String, Int)] = [
  ("mipmap-mdpi", 108),
  ("mipmap-hdpi", 162),
  ("mipmap-xhdpi", 216),
  ("mipmap-xxhdpi", 324),
  ("mipmap-xxxhdpi", 432),
]

private let androidLaunchSizes: [(String, Int)] = [
  ("mipmap-mdpi", 96),
  ("mipmap-hdpi", 144),
  ("mipmap-xhdpi", 192),
  ("mipmap-xxhdpi", 288),
  ("mipmap-xxxhdpi", 384),
]

for (directory, size) in androidLegacySizes {
  let path = root.appendingPathComponent(
    "android/app/src/main/res/\(directory)/ic_launcher.png"
  ).path
  try writePng(path: path, width: size, height: size) { context in
    drawIcon(in: context, width: size, height: size)
  }
}

for (directory, size) in androidForegroundSizes {
  let path = root.appendingPathComponent(
    "android/app/src/main/res/\(directory)/ic_launcher_foreground.png"
  ).path
  try writePng(path: path, width: size, height: size, transparent: true) { context in
    drawMark(
      in: context,
      center: CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2),
      size: CGFloat(size) * 0.46
    )
  }
}

for (directory, size) in androidLaunchSizes {
  let path = root.appendingPathComponent(
    "android/app/src/main/res/\(directory)/launch_image.png"
  ).path
  try writePng(path: path, width: size, height: size, transparent: true) { context in
    drawMark(
      in: context,
      center: CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2),
      size: CGFloat(size) * 0.42
    )
  }
}

let tvBannerPath = root.appendingPathComponent(
  "android/app/src/main/res/drawable/tv_banner.png"
).path
try writePng(path: tvBannerPath, width: 320, height: 180) { context in
  context.setFillColor(graphite)
  context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
  drawMark(in: context, center: CGPoint(x: 76, y: 90), size: 58)
  drawWordmark(in: context, at: CGPoint(x: 120, y: 78))
}

let iosIconDirectory = root.appendingPathComponent(
  "ios/Runner/Assets.xcassets/AppIcon.appiconset"
)
let iosIconSizes: [(String, Int)] = [
  ("Icon-App-20x20@1x.png", 20),
  ("Icon-App-20x20@2x.png", 40),
  ("Icon-App-20x20@3x.png", 60),
  ("Icon-App-29x29@1x.png", 29),
  ("Icon-App-29x29@2x.png", 58),
  ("Icon-App-29x29@3x.png", 87),
  ("Icon-App-40x40@1x.png", 40),
  ("Icon-App-40x40@2x.png", 80),
  ("Icon-App-40x40@3x.png", 120),
  ("Icon-App-60x60@2x.png", 120),
  ("Icon-App-60x60@3x.png", 180),
  ("Icon-App-76x76@1x.png", 76),
  ("Icon-App-76x76@2x.png", 152),
  ("Icon-App-83.5x83.5@2x.png", 167),
  ("Icon-App-1024x1024@1x.png", 1024),
]

for (name, size) in iosIconSizes {
  try writePng(
    path: iosIconDirectory.appendingPathComponent(name).path,
    width: size,
    height: size
  ) { context in
    drawIcon(in: context, width: size, height: size)
  }
}

let iosLaunchDirectory = root.appendingPathComponent(
  "ios/Runner/Assets.xcassets/LaunchImage.imageset"
)
for (name, size) in [
  ("LaunchImage.png", 96),
  ("LaunchImage@2x.png", 192),
  ("LaunchImage@3x.png", 288),
] {
  try writePng(
    path: iosLaunchDirectory.appendingPathComponent(name).path,
    width: size,
    height: size,
    transparent: true
  ) { context in
    drawMark(
      in: context,
      center: CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2),
      size: CGFloat(size) * 0.72
    )
  }
}
