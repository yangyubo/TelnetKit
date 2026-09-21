import Foundation

let parsed = ClientArguments.parse(Array(CommandLine.arguments.dropFirst()))

switch parsed {
case .help(let text):
    print(text)

case .refused(let message):
    FileHandle.standardError.write(Data(("telnetkit-client: \(message)\n").utf8))
    FileHandle.standardError.write(Data((ClientArguments.usage + "\n").utf8))
    exit(2)

case .run(let arguments):
    for warning in arguments.warnings {
        FileHandle.standardError.write(Data(("telnetkit-client: \(warning)\n").utf8))
    }
    let client = TelnetClient(arguments: arguments)
    await client.run()
}
