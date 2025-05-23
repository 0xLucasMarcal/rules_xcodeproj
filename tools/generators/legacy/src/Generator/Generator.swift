import Foundation
import PathKit
import ToolCommon
import XcodeProj

/// A class that generates and writes to disk an Xcode project.
///
/// The `Generator` class is stateless. It can be used to generate multiple
/// projects. The `generate()` method is passed all the inputs needed to
/// generate a project.
class Generator {
    static let defaultEnvironment = Environment(
        createProject: Generator.createProject,
        calculateXcodeGeneratedFiles: Generator.calculateXcodeGeneratedFiles,
        consolidateTargets: Generator.consolidateTargets,
        createFilesAndGroups: Generator.createFilesAndGroups,
        setAdditionalProjectConfiguration:
            Generator.setAdditionalProjectConfiguration,
        createProducts: Generator.createProducts,
        populateMainGroup: populateMainGroup,
        disambiguateTargets: Generator.disambiguateTargets,
        addBazelDependenciesTarget: Generator.addBazelDependenciesTarget,
        addTargets: Generator.addTargets,
        setTargetConfigurations: Generator.setTargetConfigurations,
        setTargetDependencies: Generator.setTargetDependencies,
        createCustomXCSchemes: Generator.createCustomXCSchemes,
        createAutogeneratedXCSchemes: Generator.createAutogeneratedXCSchemes,
        createXCSharedData: Generator.createXCSharedData,
        createXCUserData: Generator.createXCUserData,
        createXcodeProj: Generator.createXcodeProj,
        writeXcodeProj: Generator.writeXcodeProj
    )

    let environment: Environment
    let logger: Logger

    init(
        environment: Environment = Generator.defaultEnvironment,
        logger: Logger
    ) {
        self.logger = logger
        self.environment = environment
    }

    /// Generates an Xcode project for a given `Project`.
    func generate(
        buildMode: BuildMode,
        forFixtures: Bool,
        project: Project,
        xccurrentversions: [XCCurrentVersion],
        extensionPointIdentifiers: [TargetID: ExtensionPointIdentifier],
        directories: Directories,
        outputPath: Path
    ) async throws {
        let pbxProj = environment.createProject(
            buildMode,
            forFixtures,
            project,
            directories,
            project.legacyIndexImport,
            project.indexImport,
            project.minimumXcodeVersion
        )
        guard let pbxProject = pbxProj.rootObject else {
            throw PreconditionError(message: """
`rootObject` not set on `pbxProj`
""")
        }
        let mainGroup: PBXGroup = pbxProject.mainGroup

        let targets = project.targets

        async let (
            files,
            rootElements,
            compileStub,
            resolvedRepositories,
            internalFiles
        ) = Task {
            try environment.createFilesAndGroups(
                pbxProj,
                buildMode,
                project.options.developmentRegion,
                forFixtures,
                targets,
                project.extraFiles,
                xccurrentversions,
                directories,
                logger
            )
        }.value

        let consolidatedTargetsTask = Task {
            let xcodeGeneratedFiles = try environment
                .calculateXcodeGeneratedFiles(
                    buildMode,
                    targets
                )
            return try environment.consolidateTargets(
                targets,
                xcodeGeneratedFiles,
                logger
            )
        }

        async let disambiguatedTargets = Task {
            try await environment.disambiguateTargets(
                consolidatedTargetsTask.value,
                project.targetNameMode
            )
        }.value
        let createdProductsTask = Task {
            try await environment.createProducts(
                pbxProj,
                consolidatedTargetsTask.value
            )
        }

        try await environment.setAdditionalProjectConfiguration(
            pbxProj,
            resolvedRepositories
        )
        let (products, productsGroup) = try await createdProductsTask.value
        try await environment.populateMainGroup(
            mainGroup,
            pbxProj,
            rootElements,
            productsGroup
        )
        let bazelDependencies = try await environment
            .addBazelDependenciesTarget(
                pbxProj,
                buildMode,
                project.minimumXcodeVersion,
                project.xcodeConfigurations,
                project.defaultXcodeConfiguration,
                project.targetIdsFile,
                project.bazelConfig,
                project.preBuildScript,
                project.postBuildScript,
                consolidatedTargetsTask.value
            )
        let pbxTargets = try await environment.addTargets(
            pbxProj,
            disambiguatedTargets,
            buildMode,
            products,
            files,
            compileStub
        )
        try await environment.setTargetConfigurations(
            pbxProj,
            disambiguatedTargets,
            targets,
            buildMode,
            project.minimumXcodeVersion,
            project.xcodeConfigurations,
            project.defaultXcodeConfiguration,
            pbxTargets,
            project.targetHosts,
            bazelDependencies != nil
        )
        try await environment.setTargetDependencies(
            buildMode,
            disambiguatedTargets,
            pbxTargets,
            bazelDependencies
        )

        let targetResolver = try await TargetResolver(
            referencedContainer: directories.containerReference,
            targets: targets,
            targetHosts: project.targetHosts,
            extensionPointIdentifiers: extensionPointIdentifiers,
            consolidatedTargetKeys: disambiguatedTargets.keys,
            pbxTargets: pbxTargets
        )

        let customSchemes = try environment.createCustomXCSchemes(
            project.customXcodeSchemes,
            buildMode,
            project.xcodeConfigurations,
            project.defaultXcodeConfiguration,
            targetResolver,
            project.runnerLabel,
            project.args,
            project.envs
        )
        let autogeneratedSchemes = try environment.createAutogeneratedXCSchemes(
            project.schemeAutogenerationMode,
            buildMode,
            targetResolver,
            Set(customSchemes.map(\.name)),
            project.args,
            project.envs
        )

        let userData = environment.createXCUserData(
            NSUserName(),
            customSchemes,
            autogeneratedSchemes
        )

        let sharedData = environment.createXCSharedData(
            customSchemes + autogeneratedSchemes.map(\.scheme)
        )

        let xcodeProj = environment.createXcodeProj(
            pbxProj,
            sharedData,
            userData
        )
        try await environment.writeXcodeProj(
            xcodeProj,
            directories,
            internalFiles,
            outputPath
        )
    }
}
