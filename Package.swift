import PackageDescription

let package = Package(
    name: "Gaia",
    targets: [
        Target(name: "AST", dependencies: []),
        Target(name: "Parse", dependencies: ["AST"]),
        Target(name: "IRGen", dependencies: ["AST"]),
        Target(name: "JIT", dependencies: []),
        Target(name: "gaia", dependencies: ["Parse", "IRGen", "JIT"]),
    ],
    dependencies: [
        .Package(url: "https://github.com/rxwei/LLVM_C", majorVersion: 1, minor: 0)
    ]
)
