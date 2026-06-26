// swift-tools-version:5.9
//
// LOCAL / CI ENGINE VERIFICATION ONLY — not part of the iOS app build (XcodeGen builds that
// from project.yml). Compiles the pure maze/trace engine in Trace/Sources/Engine as the
// `TraceCore` module so the generation + trace rules can be unit-tested with `swift test` on
// any machine. The SAME files are compiled into the iOS `Trace` target.
import PackageDescription

let package = Package(
    name: "TraceCore",
    products: [.library(name: "TraceCore", targets: ["TraceCore"])],
    targets: [
        .target(name: "TraceCore", path: "Trace/Sources/Engine"),
        .testTarget(name: "TraceCoreTests", dependencies: ["TraceCore"], path: "CoreTests"),
    ]
)
