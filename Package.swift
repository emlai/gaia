import PackageDescription

let package = Package(
    name: "Gaia",
    targets: [
        Target(name: "AST", dependencies: []),
        Target(name: "Parse", dependencies: ["AST"]),
        Target(name: "IRGen", dependencies: ["AST"]),
        Target(name: "JIT", dependencies: []),
        Target(name: "REPL", dependencies: ["Parse", "AST", "IRGen", "JIT"]),
        Target(name: "Driver", dependencies: ["Parse", "AST", "IRGen"]),
        Target(name: "gaia", dependencies: ["REPL", "Driver"]),
        Target(name: "gaiac", dependencies: ["Driver"]),
    ],
    dependencies: [
        .Package(url: "https://github.com/rxwei/LLVM_C", majorVersion: 1, minor: 0)
    ]
)
