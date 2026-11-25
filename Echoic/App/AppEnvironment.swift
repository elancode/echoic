import Foundation

enum AppEnvironment {
    /// True when the app is the host process for unit tests.
    static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
