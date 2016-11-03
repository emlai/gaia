import PackageDescription

let package = Package(
    name: "Gaia",
    dependencies: [
        .Package(url: "https://github.com/rxwei/LLVM_C", majorVersion: 1, minor: 0)
    ]
)
