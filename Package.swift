// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Slate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Slate", targets: ["Slate"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.13.0")
    ],
    targets: [
        .executableTarget(
            name: "Slate",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/Slate"
        )
    ]
)
