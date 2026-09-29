import AppKit
import Foundation
import Testing
@testable import NightCrawler

@Test
func grokBotGlyphIsTheOfficialLookingUpFaceNotASlashedRobot() throws {
    let url = try #require(ProviderGlyph.grokbot.bundledResourceURL)
    let svg = try String(contentsOf: url, encoding: .utf8)
    #expect(
        !svg.contains("8.62 13.7"),
        "the invented slashed-robot mark must not ship as Grok Bot"
    )

    let image = try #require(NSImage(contentsOf: url), "Grok Bot SVG must rasterize with ink")
    let raster = try GlyphRaster.make(image, size: 96)
    #expect(raster.inkCount > 400, "the official face must draw a filled blob, not an empty template")

    let holes = raster.interiorHoles()
    #expect(
        holes.count == 2,
        "the official mark is a blob with two eye cutouts, not a slashed chassis (holes=\(holes.count))"
    )

    let left = holes.min(by: { $0.centerX < $1.centerX })!
    let right = holes.max(by: { $0.centerX < $1.centerX })!
    #expect(right.centerX > left.centerX)
    #expect(
        right.centerY < left.centerY - 2,
        "the official face looks up: the right eye sits above the left, not on a level robot stare"
    )
    for hole in holes {
        #expect(
            hole.aspect >= 1.22,
            "official eyes are ovals, not circular robot dots (aspect=\(hole.aspect))"
        )
    }

    #expect(
        raster.inkWidthFraction(inTopFraction: 0.12) >= 0.32,
        "the official head is a wide round blob on top, not a thin robot antenna (width=\(raster.inkWidthFraction(inTopFraction: 0.12)))"
    )
}

private struct GlyphRaster {
    let size: Int
    let ink: [Bool]

    struct Hole {
        let centerX: Double
        let centerY: Double
        let width: Int
        let height: Int
        var aspect: Double { Double(max(width, height)) / Double(max(min(width, height), 1)) }
    }

    static func make(_ image: NSImage, size: Int) throws -> GlyphRaster {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: size * 4,
            bitsPerPixel: 32
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        var ink = Array(repeating: false, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let color = rep.colorAt(x: x, y: y)
                ink[y * size + x] = (color?.alphaComponent ?? 0) > 0.16
            }
        }
        return GlyphRaster(size: size, ink: ink)
    }

    var inkCount: Int { ink.filter { $0 }.count }

    func inkWidthFraction(inTopFraction fraction: Double) -> Double {
        let maxY = max(Int((Double(size) * fraction).rounded()), 1)
        var minX = size
        var maxX = -1
        for y in 0..<maxY {
            for x in 0..<size where ink[y * size + x] {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        guard maxX >= minX else { return 0 }
        return Double(maxX - minX + 1) / Double(size)
    }

    func interiorHoles() -> [Hole] {
        var seen = Array(repeating: false, count: size * size)
        var stack: [Int] = []
        func index(_ x: Int, _ y: Int) -> Int { y * size + x }
        func flood(_ startX: Int, _ startY: Int) {
            stack.append(index(startX, startY))
            seen[index(startX, startY)] = true
            while let i = stack.popLast() {
                let x = i % size
                let y = i / size
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                    guard nx >= 0, ny >= 0, nx < size, ny < size else { continue }
                    let ni = index(nx, ny)
                    guard !seen[ni], !ink[ni] else { continue }
                    seen[ni] = true
                    stack.append(ni)
                }
            }
        }

        for x in 0..<size {
            if !ink[index(x, 0)], !seen[index(x, 0)] { flood(x, 0) }
            if !ink[index(x, size - 1)], !seen[index(x, size - 1)] { flood(x, size - 1) }
        }
        for y in 0..<size {
            if !ink[index(0, y)], !seen[index(0, y)] { flood(0, y) }
            if !ink[index(size - 1, y)], !seen[index(size - 1, y)] { flood(size - 1, y) }
        }

        var holes: [Hole] = []
        for y in 0..<size {
            for x in 0..<size {
                let i = index(x, y)
                guard !ink[i], !seen[i] else { continue }
                var minX = x, maxX = x, minY = y, maxY = y
                var sumX = 0, sumY = 0, count = 0
                var queue = [i]
                seen[i] = true
                while let q = queue.popLast() {
                    let qx = q % size
                    let qy = q / size
                    minX = min(minX, qx); maxX = max(maxX, qx)
                    minY = min(minY, qy); maxY = max(maxY, qy)
                    sumX += qx; sumY += qy; count += 1
                    for (nx, ny) in [(qx - 1, qy), (qx + 1, qy), (qx, qy - 1), (qx, qy + 1)] {
                        guard nx >= 0, ny >= 0, nx < size, ny < size else { continue }
                        let ni = index(nx, ny)
                        guard !seen[ni], !ink[ni] else { continue }
                        seen[ni] = true
                        queue.append(ni)
                    }
                }
                if count >= 20 {
                    holes.append(Hole(
                        centerX: Double(sumX) / Double(count),
                        centerY: Double(sumY) / Double(count),
                        width: maxX - minX + 1,
                        height: maxY - minY + 1
                    ))
                }
            }
        }
        return holes
    }
}
