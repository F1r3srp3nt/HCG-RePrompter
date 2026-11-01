// swift-tools-version: 6.0
//
// HCG RePrompter — Hakmi Capital Group
//
// The Foundation-only modules (Core, Providers, Persistence) build on any
// platform with a Swift 6 toolchain so their tests can run in CI containers.
// The SwiftUI interface and the application target are macOS-only.

import PackageDescription

var products: [Product] = [
    .library(name: "RePrompterCore", targets: ["RePrompterCore"]),
    .library(name: "RePrompterProviders", targets: ["RePrompterProviders"]),
    .library(name: "RePrompterPersistence", targets: ["RePrompterPersistence"]),
]

var targets: [Target] = [
    .target(name: "RePrompterCore"),
    .target(name: "RePrompterProviders", dependencies: ["RePrompterCore"]),
    .target(name: "RePrompterPersistence", dependencies: ["RePrompterCore", "RePrompterProviders"]),
    .testTarget(
        name: "RePrompterTests",
        dependencies: ["RePrompterCore", "RePrompterProviders", "RePrompterPersistence"]
    ),
]

#if os(macOS)
products.append(.library(name: "RePrompterUI", targets: ["RePrompterUI"]))
products.append(.executable(name: "RePrompter", targets: ["RePrompterApp"]))
targets += [
    .target(
        name: "RePrompterUI",
        dependencies: ["RePrompterCore", "RePrompterProviders", "RePrompterPersistence"]
    ),
    .executableTarget(name: "RePrompterApp", dependencies: ["RePrompterUI"]),
    .testTarget(name: "RePrompterUITests", dependencies: ["RePrompterUI"]),
]
#endif

let package = Package(
    name: "HCGRePrompter",
    platforms: [.macOS(.v15)],
    products: products,
    targets: targets
)
