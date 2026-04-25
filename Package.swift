// swift-tools-version: 5.9

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "utv",
    platforms: [
        .macOS(.v14),
        .tvOS(.v17),
    ],
    products: [
        // Library products consumed by both the macOS executable (below) and the
        // tvOS Xcode app target (see tvos/project.yml — XcodeGen-generated).
        .library(name: "utvCore", targets: ["utvCore"]),
        .library(name: "UtvWebKitTV", targets: ["UtvWebKitTV"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "602.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "utv",
            dependencies: ["utvCore"],
            path: "Sources/utv"
        ),
        .target(
            name: "utvCore",
            dependencies: [
                "UtvMacros",
                "UtvWebKitTV",
                .target(name: "VendoredWebKit", condition: .when(platforms: [.tvOS])),
            ],
            path: "Sources/utvCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "UtvWebKitTV",
            dependencies: [
                .target(name: "VendoredWebKit", condition: .when(platforms: [.tvOS])),
            ],
            path: "Sources/UtvWebKitTV",
            publicHeadersPath: "include",
            cSettings: [
                // tvOS-only: vendored WebKit headers live in the VendoredWebKit target so a single
                // copy serves both UtvWebKitTV's #imports and VendoredWebKit's `module WebKit` shim.
                .headerSearchPath("../VendoredWebKit/include", .when(platforms: [.tvOS])),
            ],
            linkerSettings: [
                // tvOS WebKit has no link-time stub. Defer unresolved symbols (_OBJC_CLASS_$_WKWebView etc.)
                // to runtime resolution; UtvWebKitBootstrap() dlopens the framework before first use.
                .unsafeFlags(["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"], .when(platforms: [.tvOS])),
            ]
        ),
        .target(
            // Re-publishes the vendored iOS-SDK WebKit headers as `module WebKit` for tvOS Swift code.
            // Conditionally depended on by `utv` only for tvOS — invisible on macOS, where Swift's
            // `import WebKit` resolves to the system framework.
            name: "VendoredWebKit",
            path: "Sources/VendoredWebKit",
            publicHeadersPath: "include"
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
