import Foundation
import Vapor

struct Runner {
    private let version: String
    private let sandboxPath: URL

    init(version: String, sandboxPath: URL) {
        self.version = version
        self.sandboxPath = sandboxPath
    }

    func run(parameter: ExecutionRequestParameter) async throws -> ExecutionResponse {
        let parameter = try Parameter(version: version, parameter: parameter)

        let command = parameter.command
        let options = parameter.options
        let timeout = parameter.timeout
        let nonce = parameter.nonce
        let envVars = parameter.environment
        let image = parameter.image
        let code = parameter.code

        let random = UUID().uuidString
        let directory = "\(nonce)_\(random)"
        let temporaryDirectory =  URL(fileURLWithPath: NSTemporaryDirectory())
        let temporaryPath = temporaryDirectory.appendingPathComponent(directory)
        WorkingDirectoryRegistry.shared.register(prefix: nonce, path: temporaryPath)

        let fileManager = FileManager()
        do {
            try fileManager.createDirectory(at: temporaryPath.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try fileManager.copyItem(at: sandboxPath, to: temporaryPath)

            try """
                import Glibc
                setbuf(stdout, nil)

                /* Start user code. Do not edit comment generated here */
                \(code)
                /* End user code. Do not edit comment generated here */
                """
                .data(using: .utf8)?
                .write(to: temporaryPath.appendingPathComponent("main.swift"))

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                temporaryPath.appendingPathComponent("sandbox.sh").path,
                "\(timeout)s",
                "--volume",
                "\(temporaryPath.path):/TEMP",
                image,
                "sh",
                "/TEMP/run.sh",
                [command, options].joined(separator: " "),
            ]
            process.environment = envVars
            process.run()
        } catch {
            WorkingDirectoryRegistry.shared.remove(path: temporaryPath)
            try? fileManager.removeItem(at: temporaryPath)
            throw error
        }

        return try await observe(workspace: temporaryPath, timeout: timeout)
    }

    private func observe(workspace path: URL, timeout: Int) async throws -> ExecutionResponse {
        let interval = 200
        let timer = DispatchSource.makeTimerSource()

        let versionPath = path.appendingPathComponent("version")
        let stdoutPath = path.appendingPathComponent("stdout")
        let stderrPath = path.appendingPathComponent("stderr")
        let statusPath = path.appendingPathComponent("status")

        let fileManager = FileManager()

        return await withCheckedContinuation { (continuation) in
            timer.setEventHandler {
                let version = (try? String(contentsOf: versionPath)) ?? "N/A"
                let stdout = (try? String(contentsOf: stdoutPath)) ?? ""
                let stderr = (try? String(contentsOf: stderrPath)) ?? ""

                let status = try? String(contentsOf: statusPath)
                guard let status = status, !status.isEmpty else {
                    return
                }

                let isTimeout = status.trimmingCharacters(in: .whitespacesAndNewlines) == "timeout"
                let timeoutMessage = isTimeout ? "Maximum execution time of \(timeout) seconds exceeded.\n" : ""

                WorkingDirectoryRegistry.shared.remove(path: path);
                try? fileManager.removeItem(at: path)
                timer.cancel()

                continuation.resume(
                    with: .success(
                        ExecutionResponse(
                            output: stdout,
                            errors: fixLineNumber(message: stderr + timeoutMessage),
                            version: version
                        )
                    )
                )
            }
            timer.schedule(deadline: .now() + .milliseconds(interval), repeating: .milliseconds(interval))
            timer.resume()
        }
    }

    private struct Parameter {
        let command: String
        let options: String
        let timeout: Int
        let environment: [String: String]
        let image: String
        let code: String
        let nonce: String

        init(version: String, parameter: ExecutionRequestParameter) throws {
            let command = parameter.command ?? "swift"
            let options = parameter.options ?? {
                if version.compare("5.3", options: .numeric) != .orderedAscending {
                    return "-I ./swiftfiddle.com/_Packages/.build/release/ -L ./swiftfiddle.com/_Packages/.build/release/ -l_Packages"
                }
                return ""
            }()
            let timeout = parameter.timeout ?? 60 // Default timeout is 60 seconds
            let color = parameter._color ?? false
            let nonce = parameter._nonce ?? ""

            var environment = ProcessInfo.processInfo.environment
            environment["_COLOR"] = "\(color)"

            guard ["swift", "swiftc"].contains(command) else { throw Abort(.badRequest) }

            // Security check
            if [";", "&", "&&", "||", "`", "(", ")", "#"].contains(where: { options.contains($0) }) {
                throw Abort(.badRequest)
            }

            guard let code = parameter.code else { throw Abort(.badRequest) }

            self.command = command
            self.options = options
            self.timeout = max(30, min(600, timeout))
            self.nonce = nonce
            self.environment = environment
            self.image = imageTag(from: version)
            self.code = code
        }
    }
}

func imageTag(from version: String) -> String {
    let image: String
    if version.hasPrefix("nightly") {
        image = "swiftlang/swift:\(version)"
    } else {
        image = "swiftfiddle/swift:\(version)"
    }
    return image
}

let regex = try! NSRegularExpression(pattern: #"\/main\.swift:(\d+):(\d+):\s"#, options: [])
func fixLineNumber(message: String) -> String {
    var message = message.replacingOccurrences(of: "/[REDACTED]", with: "")

    let matches = regex.matches(
        in: message,
        options: [],
        range: NSRange(location: 0, length: message.utf16.count)
    )

    var offset = 0
    for match in matches {
        let replacement = regex.replacementString(for: match, in: message, offset: offset, template: "$1")

        guard let replacement = Int(replacement) else { continue }
        guard match.numberOfRanges != 2 else { continue }

        var range = match.range(at: 1)
        range.location += offset

        let fixed = "\(replacement - 4)"

        let start = message.index(message.startIndex, offsetBy: range.location)
        let end = message.index(start, offsetBy: range.length)
        message = message.replacingCharacters(in: start..<end, with: fixed)
        offset += fixed.utf16.count - range.length
    }

    return message
}
