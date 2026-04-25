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
            dependencies: ["UtvMacros", "UtvWebKitTV"],
            path: "Sources",
            exclude: [
                "utv.entitlements",
                "UtvWebKitTV",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "UtvWebKitTV",
            path: "Sources/UtvWebKitTV",
            publicHeadersPath: "include",
            cSettings: [
                // tvOS-only: vendored WebKit headers (gitignored, populated by `just sync-webkit-headers`).
                .headerSearchPath("include", .when(platforms: [.tvOS])),
            ],
            linkerSettings: [
                // tvOS WebKit has no link-time stub. Defer unresolved symbols (_OBJC_CLASS_$_WKWebView etc.)
                // to runtime resolution; UtvWebKitBootstrap() dlopens the framework before first use.
                .unsafeFlags(["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"], .when(platforms: [.tvOS])),
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
