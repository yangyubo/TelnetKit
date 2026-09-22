import SwiftUI

/// The root layout.
///
/// macOS shows the control column beside a session column; iOS shows the same panels as
/// tabs, because a phone cannot hold two columns. Both read one `DemoModel`.
struct ContentView: View {
    @Bindable var model: DemoModel

    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    var body: some View {
        VStack(spacing: 0) {
            StatusBarView(model: model)
            Divider()
            layout
        }
        #if os(iOS)
        // Telnet is a foreground protocol here: the library keeps no background daemon, so
        // the demo closes the connection when the app is backgrounded.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.disconnect() }
        }
        #endif
    }

    #if os(macOS)
    private var layout: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ConnectionPanel(model: model)
                    OptionChecklist(model: model)
                    OptionStatusView(model: model)
                }
                .padding(12)
            }
            .frame(width: 400)
            Divider()
            TabView {
                SessionColumn(model: model)
                    .tabItem { Label("Session", systemImage: "terminal") }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ProtocolOperationsPanel(model: model)
                        CapabilitiesPanel(model: model)
                        ErrorInjectionPanel(model: model)
                        ValueCatalogPanel()
                    }
                    .padding(12)
                }
                .tabItem { Label("Protocol", systemImage: "arrow.left.arrow.right") }
                LogPanelView(model: model)
                    .tabItem { Label("Log", systemImage: "text.alignleft") }
            }
        }
    }
    #else
    private var layout: some View {
        TabView {
            SessionColumn(model: model)
                .tabItem { Label("Session", systemImage: "terminal") }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ConnectionPanel(model: model)
                    OptionChecklist(model: model)
                }
                .padding(12)
            }
            .tabItem { Label("Connection", systemImage: "slider.horizontal.3") }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ProtocolOperationsPanel(model: model)
                    CapabilitiesPanel(model: model)
                    ErrorInjectionPanel(model: model)
                    ValueCatalogPanel()
                }
                .padding(12)
            }
            .tabItem { Label("Protocol", systemImage: "arrow.left.arrow.right") }
            EventLogView(model: model)
                .tabItem { Label("Events", systemImage: "list.bullet.rectangle") }
            LogPanelView(model: model)
                .tabItem { Label("Log", systemImage: "text.alignleft") }
        }
    }
    #endif
}

/// Connection state, the connect control, and the last error.
struct StatusBarView: View {
    @Bindable var model: DemoModel

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(model.isConnected ? Color.green : Color.secondary)
                .frame(width: 10, height: 10)
            Text(model.statusText)
                .font(.callout)
                .lineLimit(1)

            if let remote = model.remoteAddress {
                Label(remote, systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let local = model.localAddress {
                Label(local, systemImage: "rectangle.connected.to.line.below")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let size = model.lastReportedSize {
                Text("NAWS \(size)")
                    .font(.caption)
                    .foregroundStyle(model.windowSizeArmed ? .green : .secondary)
            }
            if model.terminalTypeRequestPending {
                Text("TTYPE SEND pending")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 8)

            if let error = model.lastErrorText {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if model.isConnecting {
                Button("Cancel") { model.cancelConnectAttempt() }
            }
            Button(model.isConnected ? "Disconnect" : "Connect") {
                if model.isConnected {
                    model.disconnect()
                } else {
                    model.connect()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isConnecting)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// The session column: terminal output, the input bar, and the event log.
struct SessionColumn: View {
    @Bindable var model: DemoModel

    var body: some View {
        VStack(spacing: 0) {
            TerminalView(model: model)
                .frame(maxHeight: .infinity)
            Divider()
            InputBarView(model: model)
            Divider()
            EventLogView(model: model)
                .frame(height: 260)
        }
    }
}
