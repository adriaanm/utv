// swift-tools-version: 5.9

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "utv",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "602.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "utv",
            dependencies: ["UtvMacros"],
            path: "Sources",
            exclude: [
                "utv.entitlements",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .macro(
            name: "UtvMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Macros/UtvMacros"
        ),
    ]
)
