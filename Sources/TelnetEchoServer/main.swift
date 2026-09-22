import Foundation

let parsed = ServerArguments.parse(Array(CommandLine.arguments.dropFirst()))

switch parsed {
case .help(let text):
    print(text)

case .refused(let message):
    FileHandle.standardError.write(Data(("telnetkit-echo-server: \(message)\n").utf8))
    FileHandle.standardError.write(Data((ServerArguments.usage + "\n").utf8))
    exit(2)

case .run(let arguments):
    do {
        try await EchoServer(arguments: arguments).run()
    } catch {
        FileHandle.standardError.write(Data(("telnetkit-echo-server: \(error)\n").utf8))
        exit(1)
    }
}
