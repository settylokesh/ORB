// swift-tools-version: 5.9
//
// Vendored from github.com/google-ai-edge/LiteRT-LM (Apache-2.0), release
// v0.13.1 (commit a0afb5a56acd106b23a2b2385b8469834dc268c0).
//
// Why this is a LOCAL package rather than a remote SwiftPM dependency: the
// LiteRTLM target requires the `-all_load` unsafe linker flag (LiteRT registers
// its ops/kernels via static initializers that the linker would otherwise dead-
// strip). Xcode refuses to link a *remote* SwiftPM product that uses unsafe
// flags into an app target — even pinned by revision. A local (path-based)
// package is exempt, so ORB vendors the thin Swift wrapper here. The macOS
// xcframework itself is NOT vendored — it still downloads automatically from the
// GitHub release on first resolve (~43 MB), so a fresh clone needs no setup.
//
// Trimmed to macOS only (ORB is Apple-silicon mac) and to the library product;
// the iOS binary target and the upstream test targets are dropped.

import PackageDescription

let package = Package(
  name: "LiteRTLM",
  platforms: [
    .macOS(.v12),
  ],
  products: [
    .library(name: "LiteRTLM", targets: ["LiteRTLM"]),
  ],
  targets: [
    .binaryTarget(
      name: "CLiteRTLM_mac",
      url: "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.13.0/CLiteRTLM_mac.xcframework.zip",
      checksum: "5b5ca1d15763924247cc27931e2ab099f39fb06a12376df01d1f8f6242f1cec3"
    ),
    .target(
      name: "LiteRTLM",
      dependencies: ["CLiteRTLM_mac"],
      path: "swift",
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-all_load"])
      ]
    ),
  ]
)
