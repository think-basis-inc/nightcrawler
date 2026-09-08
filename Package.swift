// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NightCrawler",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NightCrawler", targets: ["NightCrawler"])
    ],
    targets: [
        .executableTarget(
            name: "NightCrawler",
            path: "Sources/NightCrawler",
            resources: [.copy("Resources/ProviderGlyphs")]
        ),
        .testTarget(
            name: "NightCrawlerTests",
            dependencies: ["NightCrawler"],
            path: "Tests/NightCrawlerTests",
            exclude: ["Fixtures"]
        )
    ]
)
