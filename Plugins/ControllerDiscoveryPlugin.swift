import Foundation
import PackagePlugin

enum ControllerDiscoveryPluginError: Error {
    case missingControllersDirectory
}
 
@main
struct ControllerDiscoveryPlugin: BuildToolPlugin {
    
    @available(_PackageDescription 6.0)
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        let targetDirectoryURL = URL(filePath: target.directory.string)
        let controllersDirectory = targetDirectoryURL.appending(component: "Controllers")
        let tempDirectory = context.pluginWorkDirectoryURL.appending(component: "tmp")
        let outputDirectory = context.pluginWorkDirectoryURL.appending(component: "generated")
        
        do {
            let inputPaths: [URL] = try copyFiles(from: controllersDirectory, to: tempDirectory)
            let outputPaths: [URL] = [
                outputDirectory.appending(component: "ControllerDiscovery.generated.swift")
            ]
            return [
                Command.buildCommand(
                    displayName: "ControllerDiscoveryCLI",
                    executable: try context.tool(named: "ControllerDiscoveryCLI").url,
                    arguments: [
                        target.name,
                        tempDirectory.path(),
                        outputDirectory.path(),
                    ],
                    inputFiles: inputPaths,
                    outputFiles: outputPaths
                )
            ]
        } catch ControllerDiscoveryPluginError.missingControllersDirectory {
            return []
        }
    }
    
    func copyFiles(
        from controllersDirectory: URL,
        to tempDirectory: URL
    ) throws -> [URL] {
        /// Delete `tempDirectory` if it exists (from a previous run)
        if FileManager.default.fileExists(atPath: tempDirectory.path(), isDirectory: nil) {
            try FileManager.default.removeItem(atPath: tempDirectory.path())
        }
        
        guard let enumerator = FileManager.default.enumerator(atPath: controllersDirectory.path()) else {
            return []
        }
        
        try FileManager.default.copyItem(
            atPath: controllersDirectory.path(),
            toPath: tempDirectory.path())
        
        var inputPaths: [URL] = []
        while let file = enumerator.nextObject() as? String {
            let swiftSuffix = ".swift"
            guard file.hasSuffix(swiftSuffix) else {
                continue
            }
            let inputPath = controllersDirectory.appending(component: file)
            inputPaths.append(inputPath)
        }
        return inputPaths
    }
}
