import SwiftUI
import TelnetKit

/// `optionStatus(_:)` for every modeled option.
///
/// The ledger is derived from observed negotiation, so the table changes as events arrive;
/// `Refresh` reads it again on demand.
struct OptionStatusView: View {
    @Bindable var model: DemoModel

    var body: some View {
        GroupBox("optionStatus(_:)") {
            VStack(alignment: .leading, spacing: 6) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("option").bold()
                        Text("locally Enabled").bold()
                        Text("remote Enabled").bold()
                        Text("local Requested").bold()
                        Text("remote Requested").bold()
                    }
                    ForEach(TelnetOption.allCases, id: \.self) { option in
                        GridRow {
                            Text(option.displayName).font(.callout)
                            flag(model.optionStatuses[option]?.locallyEnabled)
                            flag(model.optionStatuses[option]?.remotelyEnabled)
                            flag(model.optionStatuses[option]?.localRequested)
                            flag(model.optionStatuses[option]?.remoteRequested)
                        }
                    }
                }
                Button("Refresh") {
                    Task { await model.refreshOptionStatuses() }
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func flag(_ value: Bool?) -> some View {
        switch value {
        case true: Text("yes").font(.caption).foregroundStyle(.green)
        case false: Text("no").font(.caption).foregroundStyle(.secondary)
        case nil: Text("—").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// `negotiate(_:option:)`, `requestOption(_:)`, `subnegotiate(option:payload:)`, and
/// `send(command:)`.
struct ProtocolOperationsPanel: View {
    @Bindable var model: DemoModel

    var body: some View {
        GroupBox("Manual protocol operations") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Picker("verb", selection: $model.negotiationAction) {
                        ForEach(TelnetNegotiation.allCases, id: \.self) { action in
                            Text(action.demoName).tag(action)
                        }
                    }
                    Picker("option", selection: $model.negotiationOption) {
                        ForEach(TelnetOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Button("negotiate(_:option:)") { model.negotiateSelection() }
                }

                HStack(spacing: 8) {
                    Picker("option", selection: $model.requestOptionSelection) {
                        ForEach(TelnetOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Button("requestOption(_:)") { model.requestSelectedOption() }
                }

                HStack(spacing: 8) {
                    Picker("option", selection: $model.subnegotiationOption) {
                        ForEach(TelnetOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    TextField("payload hex", text: $model.subnegotiationHex)
                        .textFieldStyle(.roundedBorder)
                    Button("subnegotiate(option:payload:)") { model.sendSubnegotiation() }
                }

                HStack(spacing: 8) {
                    Picker("command", selection: $model.selectedCommand) {
                        ForEach(TelnetCommand.allCases, id: \.self) { command in
                            Text(command.demoName).tag(command)
                        }
                    }
                    Button("send(command:)") { model.sendSelectedCommand() }
                }

                HStack(spacing: 8) {
                    TextField("unmodeled option code, empty to use the pickers", text: $model.customOptionCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Text("TelnetOption(rawValue:)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// `replyTerminalType(_:)`, `sendEnvironment(_:scope:)`, and `sendWindowSize(columns:rows:)`.
struct CapabilitiesPanel: View {
    @Bindable var model: DemoModel

    var body: some View {
        GroupBox("Terminal capabilities") {
            VStack(alignment: .leading, spacing: 8) {
                Text("A real telnetd usually withholds its login prompt until the terminal type is answered, so both answers are automatic by default. Turn a switch off to answer by hand; pressing a button with no request pending throws .invalidConfiguration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Answer TERMINAL-TYPE automatically", isOn: $model.autoAnswerTerminalType)
                Toggle("Answer NEW-ENVIRON automatically", isOn: $model.autoAnswerEnvironment)

                HStack(spacing: 8) {
                    TextField("terminal type", text: $model.terminalType)
                        .textFieldStyle(.roundedBorder)
                    Button("replyTerminalType(_:)") { model.replyTerminalType() }
                    if model.terminalTypeRequestPending {
                        Text("a request is pending").font(.caption).foregroundStyle(.green)
                    }
                }

                Divider()

                Text("NEW-ENVIRON variables").font(.caption).bold()
                ForEach($model.environmentRows) { $row in
                    HStack(spacing: 8) {
                        TextField("name", text: $row.name)
                            .textFieldStyle(.roundedBorder)
                        TextField("value", text: $row.value)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                HStack(spacing: 8) {
                    Button("Add variable") {
                        model.environmentRows.append(DemoEnvironmentRow(name: "", value: ""))
                    }
                    .font(.caption)
                    Picker("scope", selection: $model.environmentScope) {
                        Text("variable").tag(EnvironmentScope.variable)
                        Text("userVariable").tag(EnvironmentScope.userVariable)
                    }
                    Button("sendEnvironment(_:scope:)") { model.sendEnvironmentValues() }
                }

                Divider()

                Text("Window size (NAWS)").font(.caption).bold()
                HStack(spacing: 8) {
                    TextField("columns", value: $model.manualColumns, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    TextField("rows", value: $model.manualRows, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Button("sendWindowSize(columns:rows:)") { model.sendManualWindowSize() }
                }
                Text(model.windowSizeArmed
                     ? "The peer enabled NAWS; resizing the window reports the size automatically."
                     : "NAWS is not enabled by the peer yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The reachable `TelnetError` cases, each backed by a real failure path.
struct ErrorInjectionPanel: View {
    @Bindable var model: DemoModel

    var body: some View {
        GroupBox("Error injection") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Each button reaches the failure for real. Cases this build cannot trigger are shown as values under Public values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(DemoErrorInjection.allCases) { injection in
                    HStack(spacing: 8) {
                        Button(injection.title) { model.inject(injection) }
                            .buttonStyle(.bordered)
                        Text(injection.expectedError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

/// Every public error, warning, and code value, rendered without needing live traffic.
struct ValueCatalogPanel: View {
    var body: some View {
        GroupBox("Public values") {
            VStack(alignment: .leading, spacing: 12) {
                section("TelnetError (12 cases)", DemoCatalogs.errors)
                section("TelnetWarning (5 cases)", DemoCatalogs.warnings)
                section("TelnetProtocolError (3 cases)", DemoCatalogs.protocolErrors)
                section("TelnetErrorCode (5 cases)", DemoCatalogs.errorCodes)
                section("TelnetTransportFailure.Kind (6 cases)", DemoCatalogs.transportKinds)
            }
        }
    }

    private func section(_ title: String, _ entries: [DemoValueEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).bold()
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.name)
                        .font(.caption)
                        .bold()
                        .frame(width: 180, alignment: .leading)
                    Text(entry.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
