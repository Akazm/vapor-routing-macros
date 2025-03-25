import Vapor
import Dispatch
import Logging
import VaporRoutingMacros

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Vapor.Application.make(env)
        // Registers controllers that were discovered by the ControllerDiscoveryPlugin
        app.registerControllers()
        try await app.execute()
        try await app.asyncShutdown()
    }
}
