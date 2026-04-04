// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "utv",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "utv",
            path: "utv/utv",
            exclude: [
                "utv.entitlements",
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Resources"),
            ]
        ),
    ]
)
