import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Render the canonical Thorbis shield on an opaque square canvas. iOS applies
// the icon corner mask; keep the original mark proportions and blue unchanged.
let destination = CommandLine.arguments.dropFirst().first ?? "Thorbis/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let markPath = "Thorbis/Resources/Assets.xcassets/ThorbisMark.imageset/ThorbisMark.png"
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: markPath) as CFURL, nil),
      let mark = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Cannot load the canonical Thorbis shield at \(markPath)")
}
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
        bytesPerRow: 4096, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Cannot create icon drawing context")
}
context.setFillColor(CGColor(red: 17/255, green: 18/255, blue: 19/255, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.interpolationQuality = .high
context.draw(mark, in: CGRect(x: 64, y: 64, width: 896, height: 896))
guard let image = context.makeImage(),
      let output = CGImageDestinationCreateWithURL(URL(fileURLWithPath: destination) as CFURL,
        UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot encode icon") }
CGImageDestinationAddImage(output, image, nil)
precondition(CGImageDestinationFinalize(output), "Cannot write icon")
