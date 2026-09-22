import SwiftUI
import TelnetKit

/// The terminal output area.
///
/// Its `GeometryReader` is what makes window resizing observable: every size change is
/// converted into a column and row count by `DemoWindowMetrics` and becomes a NAWS report
/// once the peer has enabled the option.
struct TerminalView: View {
    @Bindable var model: DemoModel

    private static let bottomAnchor = "terminal-bottom"

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.output.isEmpty ? "No output yet." : model.output)
                        .font(.system(size: DemoWindowMetrics.terminalFontSize, design: .monospaced))
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .id(Self.bottomAnchor)
                }
                .background(Color.black)
                .onChange(of: model.output) { _, _ in
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
            .onAppear {
                model.terminalSizeChanged(width: geometry.size.width, height: geometry.size.height)
            }
            .onChange(of: geometry.size) { _, size in
                model.terminalSizeChanged(width: size.width, height: size.height)
            }
        }
    }
}

/// The four sending methods, the line-ending choice, and the raw-byte field.
struct InputBarView: View {
    @Bindable var model: DemoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Type a line, then press Return", text: $model.inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.sendCurrentLine() }
                Button("Send") { model.sendCurrentLine() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.inputText.isEmpty)
            }
            HStack(spacing: 8) {
                Picker("Line ending", selection: $model.lineEnding) {
                    ForEach(TelnetLineEnding.allCases, id: \.self) { ending in
                        Text(ending.demoName).tag(ending)
                    }
                }
                .frame(maxWidth: 220)
                Button("send(text:)") { model.sendWithDefaultLineEnding() }
                    .disabled(model.inputText.isEmpty)
                Spacer(minLength: 0)
                if !model.localEchoEnabled {
                    Text("peer echoes input")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                TextField("hex bytes, for example 68 65 6C 6C 6F", text: $model.hexBytes)
                    .textFieldStyle(.roundedBorder)
                Button("send(_:)") { model.sendHexBytes() }
                Button("sendRaw(_:)") { model.sendHexBytesRaw() }
            }
        }
        .padding(8)
    }
}

/// Every `TelnetEvent` the connection delivered, one row each, colored by case.
struct EventLogView: View {
    @Bindable var model: DemoModel

    private static let bottomAnchor = "event-bottom"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Events")
                    .font(.headline)
                Text("\(model.eventRecords.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.clearEventLog() }
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.eventRecords) { record in
                            HStack(alignment: .top, spacing: 6) {
                                Text("#\(record.sequence)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                                Text(record.name)
                                    .font(.caption)
                                    .bold()
                                    .foregroundStyle(record.category.color)
                                    .frame(width: 168, alignment: .leading)
                                Text(record.detail)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchor)
                    }
                    .padding(8)
                }
                .onChange(of: model.eventRecords.count) { _, _ in
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
        }
    }
}

/// The records the injected `Logger` produced.
struct LogPanelView: View {
    @Bindable var model: DemoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Library log")
                    .font(.headline)
                Text("\(model.logRecords.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.clearLogRecords() }
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if model.logRecords.isEmpty {
                        Text(model.settings.loggingEnabled
                             ? "No records yet."
                             : "Turn on “Inject a swift-log Logger” in the connection panel.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    ForEach(model.logRecords) { record in
                        HStack(alignment: .top, spacing: 6) {
                            Text(record.level.rawValue)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(color(for: record.level))
                                .frame(width: 60, alignment: .leading)
                            Text(record.message)
                                .font(.caption)
                            Text(record.metadata.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private func color(for level: DemoLoggerLevel) -> Color {
        switch level {
        case .trace: .secondary
        case .debug: .blue
        case .info: .green
        case .notice: .teal
        case .warning: .orange
        case .error, .critical: .red
        }
    }
}
