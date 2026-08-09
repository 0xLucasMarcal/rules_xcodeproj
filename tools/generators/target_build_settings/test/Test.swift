import OrderedCollections
import XCTest
@testable import target_build_settings

final class ProcessSwiftArgTests: XCTestCase {
    func testWholeModuleOptimizationUsesWholeModuleCompilation() throws {
        for argument in ["-whole-module-optimization", "-wmo"] {
            let result = try process(argument)

            XCTAssertEqual(result.args, [])
            XCTAssertEqual(
                result.buildSettings.map { [$0.key, $0.value] },
                [["SWIFT_COMPILATION_MODE", "wholemodule"]],
                "argument: \(argument)"
            )
        }
    }

    func testSingleFileCompilationModesRemainUnconditional() throws {
        for argument in ["-incremental", "-no-whole-module-optimization"] {
            let result = try process(argument)

            XCTAssertEqual(result.args, [])
            XCTAssertEqual(
                result.buildSettings.map { [$0.key, $0.value] },
                [["SWIFT_COMPILATION_MODE", "singlefile"]],
                "argument: \(argument)"
            )
        }
    }

    private func process(
        _ argument: String
    ) throws -> (
        args: [String],
        buildSettings: [(key: String, value: String)]
    ) {
        var args: [String] = []
        var buildSettings: [(key: String, value: String)] = []
        var frameworkIncludes = OrderedSet<String>()
        var swiftIncludes = OrderedSet<String>()

        try Generator.ProcessSwiftArg()(
            argument,
            previousArg: nil,
            previousFrontendArg: nil,
            args: &args,
            buildSettings: &buildSettings,
            frameworkIncludes: &frameworkIncludes,
            includeSelfSwiftDebugSettings: false,
            swiftIncludes: &swiftIncludes
        )

        return (args, buildSettings)
    }
}
