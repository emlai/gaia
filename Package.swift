import PackageDescription

let package = Package(
    name: "Gaia",
    targets: [
        Target(name: "AST", dependencies: []),
        Target(name: "Parse", dependencies: ["AST"]),
        Target(name: "SemanticAnalysis", dependencies: ["AST"]),
        Target(name: "IRGen", dependencies: ["AST"]),
        Target(name: "Driver", dependencies: ["Parse", "AST", "SemanticAnalysis", "IRGen"]),
        Target(name: "REPL", dependencies: ["Parse", "AST", "IRGen", "Driver"]),
        Target(name: "gaia", dependencies: ["REPL", "Driver"]),
        Target(name: "gaiac", dependencies: ["Driver"]),
    ],
    dependencies: [
        .Package(url: "https://github.com/emlai/LLVM.swift", "0.2.0")
    ]
)
