import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Render Thorbis' established geometric T at Apple's icon size. Opaque and
// square: iOS applies its own corner mask. No raster source is rescaled.
let destination = CommandLine.arguments.dropFirst().first ?? "Thorbis/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
        bytesPerRow: 4096, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Cannot create icon drawing context")
}
context.setFillColor(CGColor(red: 17/255, green: 18/255, blue: 19/255, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.setFillColor(CGColor(red: 55/255, green: 126/255, blue: 242/255, alpha: 1))
context.fill(CGRect(x: 240, y: 624, width: 544, height: 152))
context.fill(CGRect(x: 432, y: 248, width: 160, height: 376))
guard let image = context.makeImage(),
      let output = CGImageDestinationCreateWithURL(URL(fileURLWithPath: destination) as CFURL,
        UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot encode icon") }
CGImageDestinationAddImage(output, image, nil)
precondition(CGImageDestinationFinalize(output), "Cannot write icon")
