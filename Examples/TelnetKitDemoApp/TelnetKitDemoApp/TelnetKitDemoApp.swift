import SwiftUI

/// The demo application the PRD requires: an interactive Telnet terminal that covers every
/// public interface of `TelnetKit`.
///
/// The macOS and iOS targets share these sources. The app consumes the library as a caller
/// does, through `import TelnetKit` alone.
@main
struct TelnetKitDemoApp: App {
    /// One model for the app's single window. `@State` owns it for the process lifetime.
    @State private var model = DemoModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                // Closing the window closes the connection, which is the demo's
                // "disconnect on window close" contract. The library also closes the socket
                // in `deinit`, so a missed callback cannot strand it.
                .onDisappear { model.disconnect() }
                #if os(macOS)
                .frame(minWidth: 1_040, minHeight: 640)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1_180, height: 780)
        #endif
    }
}
