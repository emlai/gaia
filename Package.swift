import PackageDescription

let package = Package(
    name: "Gaia",
    targets: [
        Target(name: "AST", dependencies: []),
        Target(name: "Parse", dependencies: ["AST"]),
        Target(name: "MIR", dependencies: ["AST"]),
        Target(name: "SemanticAnalysis", dependencies: ["AST", "MIR"]),
        Target(name: "IRGen", dependencies: ["AST", "MIR"]),
        Target(name: "Driver", dependencies: ["Parse", "AST", "MIR", "SemanticAnalysis", "IRGen"]),
        Target(name: "REPL", dependencies: ["Parse", "AST", "MIR", "Driver"]),
        Target(name: "gaia", dependencies: ["REPL", "Driver"]),
        Target(name: "gaiac", dependencies: ["Driver"]),
    ],
    dependencies: [
        .Package(url: "https://github.com/emlai/LLVM.swift", "0.2.0")
    ]
)
