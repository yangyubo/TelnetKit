import SwiftUI
import TelnetKit

/// The endpoint and every `TelnetConfiguration` parameter.
struct ConnectionPanel: View {
    @Bindable var model: DemoModel

    var body: some View {
        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Host") {
                    TextField("host", text: $model.settings.host)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Port") {
                    TextField("port", value: $model.settings.port, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                LabeledContent("Connect timeout (s)") {
                    TextField("seconds", value: $model.settings.connectTimeoutSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                Toggle("Idle timeout", isOn: $model.settings.idleTimeoutEnabled)
                if model.settings.idleTimeoutEnabled {
                    LabeledContent("Idle timeout (s)") {
                        TextField("seconds", value: $model.settings.idleTimeoutSeconds, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                }
                LabeledContent("Inbound buffer limit") {
                    TextField("bytes", value: $model.settings.inboundBufferLimit, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }
                LabeledContent("Subnegotiation limit") {
                    TextField("bytes", value: $model.settings.subnegotiationLimit, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }
                Picker("Event buffer policy", selection: $model.settings.eventBufferPolicy) {
                    ForEach(DemoEventBufferPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                if model.settings.eventBufferPolicy != .unbounded {
                    LabeledContent("Event buffer count") {
                        TextField("events", value: $model.settings.eventBufferCount, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                    }
                }
                Picker("Newline policy", selection: $model.settings.newlinePolicy) {
                    ForEach(DemoNewlinePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                Toggle("Wait for connectivity", isOn: $model.settings.waitForConnectivity)
                Toggle("Inject a swift-log Logger", isOn: $model.settings.loggingEnabled)
                if model.settings.loggingEnabled {
                    Picker("Log level", selection: $model.settings.logLevel) {
                        ForEach(DemoLoggerLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                }
            }
        }
    }
}

/// Every modeled option as a `will` and a `do` checkbox.
///
/// `TelnetOption.allCases` drives the rows, so all 18 constants and `displayName` appear,
/// and `rawValue` is shown beside each name.
struct OptionChecklist: View {
    @Bindable var model: DemoModel

    var body: some View {
        GroupBox("Options offered locally (will) and requested remotely (do)") {
            VStack(alignment: .leading, spacing: 6) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Option").bold()
                        Text("will").bold()
                        Text("do").bold()
                    }
                    ForEach(TelnetOption.allCases, id: \.self) { option in
                        GridRow {
                            Text("\(option.displayName) (\(option.rawValue))")
                                .font(.callout)
                            Toggle("will \(option.displayName)", isOn: localBinding(option))
                                .labelsHidden()
                            Toggle("do \(option.displayName)", isOn: remoteBinding(option))
                                .labelsHidden()
                        }
                    }
                }
                Text(model.settings.telnetOptions.isValid
                     ? "isValid: the option set is accepted."
                     : "isValid is false: binary with lineMode in local; connect throws .invalidConfiguration.")
                    .font(.caption)
                    .foregroundStyle(model.settings.telnetOptions.isValid ? Color.secondary : Color.red)
            }
        }
    }

    private func localBinding(_ option: TelnetOption) -> Binding<Bool> {
        Binding(
            get: { model.settings.localOptions.contains(option) },
            set: { isOn in
                if isOn {
                    model.settings.localOptions.insert(option)
                } else {
                    model.settings.localOptions.remove(option)
                }
            }
        )
    }

    private func remoteBinding(_ option: TelnetOption) -> Binding<Bool> {
        Binding(
            get: { model.settings.remoteOptions.contains(option) },
            set: { isOn in
                if isOn {
                    model.settings.remoteOptions.insert(option)
                } else {
                    model.settings.remoteOptions.remove(option)
                }
            }
        )
    }
}
