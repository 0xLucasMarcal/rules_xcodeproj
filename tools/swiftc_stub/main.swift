import Foundation

// MARK: - Helpers

enum PathKey: String {
    case emitModulePath = "-emit-module-path"
    case outputPath = "-o"
    case emitModuleDocPath = "-emit-module-doc-path"
    case emitModuleSourceInfoPath = "-emit-module-source-info-path"
    case emitAbiDescriptorPath = "-emit-abi-descriptor-path"
    case emitObjCHeaderPath = "-emit-objc-header-path"
    case outputFileMap = "-output-file-map"
    case sdk = "-sdk"
}

enum IncrementalCompilationPathKey: String {
    case emitDependenciesPaths = "-emit-dependencies-path"
}

let swiftcPath: String = {
    guard let path = ProcessInfo.processInfo.environment["PATH"] else {
        fputs("error: PATH not set", stderr)
        exit(1)
    }

    var result: String?
    
    if let toolchainDir = ProcessInfo.processInfo.environment["TOOLCHAIN_DIR"] {
        result = "\(toolchainDir)/usr/bin/swiftc"
    } else {
        // /Applications/Xcode-15.0.0-Beta.app/Contents/Developer/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin -> /Applications/Xcode-15.0.0-Beta.app/Contents/Developer/usr/bin
        let pathComponents = path.split(separator: ":", maxSplits: 1)
        let xcodeBinPath = pathComponents[0]
        guard xcodeBinPath.hasSuffix("/Contents/Developer/usr/bin") else {
            fputs("Xcode based bin PATH not set \(path)", stderr)
            fputs("error: Xcode based bin PATH not set", stderr)
            exit(1)
        }
        // /Applications/Xcode-15.0.0-Beta.app/Contents/Developer/usr/bin -> /Applications/Xcode-15.0.0-Beta.app/Contents/Developer
        let developerDir = xcodeBinPath.dropLast(8)
        result = "\(developerDir)/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
    }

    guard let result else {
        fputs("error: Failed to determine swiftc path", stderr)
        exit(1)
    }

    return result
}()

func processArgs(
    _ args: [String]
) async throws -> (
    isPreviewThunk: Bool,
    isWMO: Bool,
    isEmitModule: Bool,
    paths: [PathKey: URL],
    incrementalCompilationPaths: [IncrementalCompilationPathKey: [URL]]
) {
    var isPreviewThunk = false
    var isWMO = false
    var isEmitModule = false
    var paths: [PathKey: URL] = [:]
    var incrementalCompilationPaths: [IncrementalCompilationPathKey: [URL]] = [:]

    var previousArg: String?
    func processArg(_ arg: String) {
        if let rawPathKey = previousArg {
            if let key = PathKey(rawValue: rawPathKey) {
                paths[key] = URL(fileURLWithPath: arg)
            } else if let key = IncrementalCompilationPathKey(rawValue: rawPathKey) {
                incrementalCompilationPaths[key, default: []].append(URL(fileURLWithPath: arg))
            }
            previousArg = nil
            return
        }

        if arg == "-wmo" || arg == "-whole-module-optimization" {
            isWMO = true
        } else if arg.hasSuffix(".preview-thunk.swift") || arg.hasSuffix(".preview-thunk.swift.json") {
            isPreviewThunk = true
        } else if arg == "-emit-module" {
            // swift-driver doesn't pass `-output-file-map` when building swift modules without using OutputFileMap, we must handle this case
            isEmitModule = true
        } else {
            previousArg = arg
        }
    }

    for arg in args {
        if arg.hasPrefix("@") {
            let argumentFileURL
                = URL(fileURLWithPath: String(arg.dropFirst()))
            for try await line in argumentFileURL.lines {
                if line.hasPrefix(#"""#) && line.hasSuffix(#"""#) {
                    processArg(String(line.dropFirst().dropLast()))
                } else {
                    processArg(String(line))
                }
            }
        } else {
            processArg(arg)
        }
    }

    return (
        !paths.keys.contains(.outputFileMap) && isPreviewThunk,
        isWMO,
        isEmitModule,
        paths,
        incrementalCompilationPaths
    )
}

extension URL {
    mutating func touch() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(atPath: path, contents: nil)
        } else {
            var resourceValues = URLResourceValues()
            resourceValues.contentModificationDate = Date()
            try setResourceValues(resourceValues)
        }
    }
}

/// Touch the Xcode-required `.d` files
func touchDepsFiles(isWMO: Bool, paths: [PathKey: URL], incrementalCompilationPaths: [IncrementalCompilationPathKey: [URL]]) throws {
    if let outputFileMapPath = paths[PathKey.outputFileMap] {
        if isWMO {
            let dPath = String(
                outputFileMapPath.path.dropLast("-OutputFileMap.json".count) +
                "-master.d"
            )
            var url = URL(fileURLWithPath: dPath)
            try url.touch()
        } else {
            let data = try Data(contentsOf: outputFileMapPath)
            let outputFileMapRaw = try JSONSerialization.jsonObject(
                with: data,
                options: []
            )
            guard let outputFileMap = outputFileMapRaw as? [String: [String: Any]]
            else {
                return
            }

            for entry in outputFileMap.values {
                guard let dPath = entry["dependencies"] as? String else {
                    continue
                }
                var url = URL(fileURLWithPath: dPath)
                try url.touch()
            }
        }
    } else {
        if let emitDependenciesPaths = incrementalCompilationPaths[IncrementalCompilationPathKey.emitDependenciesPaths] {
            for pathURL in emitDependenciesPaths {
                var url = URL(fileURLWithPath: pathURL.path)
                try url.touch()
            }
        }
    }
}

/// Touch the Xcode-required `.swift{module,doc,sourceinfo}` files
/// If `isEmitModule` is true, it means we're being invoked by swift-driver, which provides all the artifacts paths.
func touchSwiftmoduleArtifacts(isEmitModule: Bool, paths: [PathKey: URL]) throws {
    if var swiftmodulePath = paths[PathKey.emitModulePath] {
        var swiftdocPath = swiftmodulePath.deletingPathExtension()
            .appendingPathExtension("swiftdoc")
        var swiftsourceinfoPath = swiftmodulePath.deletingPathExtension()
            .appendingPathExtension("swiftsourceinfo")
        var swiftinterfacePath = swiftmodulePath.deletingPathExtension()
            .appendingPathExtension("swiftinterface")

        try swiftmodulePath.touch()
        try swiftdocPath.touch()
        try swiftsourceinfoPath.touch()
        try swiftinterfacePath.touch()
    } else if isEmitModule {
        var swiftDocPath = paths[PathKey.emitModuleDocPath]
        var swiftSourceInfoPath = paths[PathKey.emitModuleSourceInfoPath]
        var abiDescriptorPath = paths[PathKey.emitAbiDescriptorPath]
        var swiftModuleOutputPath = paths[PathKey.outputPath]

        try swiftDocPath?.touch()
        try swiftSourceInfoPath?.touch()
        try abiDescriptorPath?.touch()
        try swiftModuleOutputPath?.touch()
    }

    if var generatedHeaderPath = paths[PathKey.emitObjCHeaderPath] {
        try generatedHeaderPath.touch()
    }
}

func runSubProcess(executable: String, args: [String]) throws -> Int32 {
    let task = Process()
    task.launchPath = executable
    task.arguments = args
    try task.run()
    task.waitUntilExit()
    return task.terminationStatus
}

func handleXcodePreviewThunk(args: [String], paths: [PathKey: URL]) throws -> Never {
    try exit(runSubProcess(executable: swiftcPath, args: Array(args.dropFirst())))
}

// MARK: - Main


let args = CommandLine.arguments

// Xcode 16.0 Beta 3 began using "--version" over "-v". Support both.
if args.count == 2, args.last == "--version" || args.last == "-v" {
    // args.last allows passing in -v (Xcode < 16b3) and --version (>= 16b3)
    try exit(runSubProcess(executable: swiftcPath, args: [args.last!]))
}

let (
    isPreviewThunk,
    isWMO,
    isEmitModule,
    paths,
    incrementalCompilationPaths
) = try await processArgs(args)

guard !isPreviewThunk else {
    // Pass through for Xcode Preview thunk compilation
    try handleXcodePreviewThunk(args: args, paths: paths)
}

try touchDepsFiles(isWMO: isWMO, paths: paths, incrementalCompilationPaths: incrementalCompilationPaths)
try touchSwiftmoduleArtifacts(isEmitModule: isEmitModule, paths: paths)
