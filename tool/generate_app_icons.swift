// Run from the project root: swift tool/generate_app_icons.swift
// Uses the splash logo as the single source for all platform app icons.
import AppKit
import Foundation
import ImageIO

let sourcePath = "assets/images/cloudio-app-icon.png"
guard let source = NSImage(contentsOfFile: sourcePath) else {
  fatalError("Cannot load \(sourcePath)")
}

let blue = NSColor(deviceRed: 47.0 / 255, green: 140.0 / 255,
                   blue: 245.0 / 255, alpha: 1)

func png(size: Int, opaque: Bool) -> Data {
  let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
  guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: alpha.rawValue
  ) else {
    fatalError("Cannot create \(size)x\(size) bitmap")
  }

  let graphics = NSGraphicsContext(cgContext: context, flipped: false)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = graphics
  graphics.imageInterpolation = .high
  let rect = NSRect(x: 0, y: 0, width: size, height: size)
  if opaque {
    blue.setFill()
    rect.fill()
  } else {
    context.clear(rect)
  }
  source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
  graphics.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()
  guard let image = context.makeImage() else {
    fatalError("Cannot encode \(size)x\(size) PNG")
  }
  let data = NSMutableData()
  guard let destination = CGImageDestinationCreateWithData(
    data, "public.png" as CFString, 1, nil
  ) else {
    fatalError("Cannot create PNG destination")
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    fatalError("Cannot finish PNG")
  }
  return data as Data
}

func save(_ size: Int, _ path: String, opaque: Bool) throws {
  try png(size: size, opaque: opaque).write(to: URL(fileURLWithPath: path))
}

// iPhone, iPad, and App Store icons must not contain an alpha channel.
let iosFolder = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
let contents = try Data(contentsOf: URL(fileURLWithPath: "\(iosFolder)/Contents.json"))
guard let manifest = try JSONSerialization.jsonObject(with: contents) as? [String: Any],
      let images = manifest["images"] as? [[String: String]] else {
  fatalError("Cannot read iOS icon manifest")
}
for image in images {
  guard let filename = image["filename"],
        let points = image["size"]?.split(separator: "x").first,
        let pointSize = Double(points),
        let scaleText = image["scale"]?.replacingOccurrences(of: "x", with: ""),
        let scale = Double(scaleText) else { continue }
  try save(Int((pointSize * scale).rounded()), "\(iosFolder)/\(filename)",
           opaque: true)
}

let androidSizes = ["mdpi": 48, "hdpi": 72, "xhdpi": 96,
                    "xxhdpi": 144, "xxxhdpi": 192]
for (density, size) in androidSizes {
  let folder = "android/app/src/main/res/mipmap-\(density)"
  try save(size, "\(folder)/ic_launcher.png", opaque: true)
  try save(size * 9 / 4, "\(folder)/ic_launcher_foreground.png",
           opaque: false)
}

let macFolder = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
for size in [16, 32, 64, 128, 256, 512, 1024] {
  try save(size, "\(macFolder)/app_icon_\(size).png", opaque: false)
}

for size in [192, 512] {
  try save(size, "web/icons/Icon-\(size).png", opaque: false)
  try save(size, "web/icons/Icon-maskable-\(size).png", opaque: true)
}
try save(48, "web/favicon.png", opaque: false)

// Windows ICO supports PNG-compressed image entries.
func append16(_ value: UInt16, to data: inout Data) {
  data.append(UInt8(value & 0xff))
  data.append(UInt8((value >> 8) & 0xff))
}
func append32(_ value: UInt32, to data: inout Data) {
  for shift in stride(from: 0, through: 24, by: 8) {
    data.append(UInt8((value >> shift) & 0xff))
  }
}
let icoSizes = [16, 32, 48, 256]
let icoImages = icoSizes.map { png(size: $0, opaque: false) }
var ico = Data()
append16(0, to: &ico)
append16(1, to: &ico)
append16(UInt16(icoSizes.count), to: &ico)
var offset = UInt32(6 + icoSizes.count * 16)
for (size, data) in zip(icoSizes, icoImages) {
  ico.append(size == 256 ? 0 : UInt8(size))
  ico.append(size == 256 ? 0 : UInt8(size))
  ico.append(0)
  ico.append(0)
  append16(1, to: &ico)
  append16(32, to: &ico)
  append32(UInt32(data.count), to: &ico)
  append32(offset, to: &ico)
  offset += UInt32(data.count)
}
for data in icoImages { ico.append(data) }
try ico.write(to: URL(fileURLWithPath: "windows/runner/resources/app_icon.ico"))

print("Cloudio app icons generated from \(sourcePath)")
