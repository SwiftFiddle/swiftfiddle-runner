import Vapor

func routes(_ app: Application) throws {
    app.get { (req) -> [String: String] in
        let imageTag = try installedImageTag()
        return ["status": "pass", "version": imageTag,]
    }

    app.get("runner", ":version", "health") { (req) -> [String: String] in
        guard let version = req.parameters.get("version") else { throw Abort(.badRequest) }
        let imageTag = try installedImageTag()
        return [
            "status": "pass",
            "version": version,
            "installedVersion": imageTag,
        ]
    }

    app.on(.POST, "runner", ":version", "run", body: .collect(maxSize: "10mb")) { (req) -> EventLoopFuture<ExecutionResponse> in
        guard let version = req.parameters.get("version") else { throw Abort(.badRequest) }
        
        let parameter = try req.content.decode(ExecutionRequestParameter.self)
        let sandboxPath = URL(fileURLWithPath: "\(app.directory.resourcesDirectory)Sandbox")
        let runner = Runner( version: version, sandboxPath: sandboxPath)

        let promise = req.eventLoop.makePromise(of: ExecutionResponse.self)
        do {
            try runner.run(
                parameter: parameter,
                onComplete: { (response) in
                    promise.succeed(response)
                },
                onTimeout: { (response) in
                    promise.succeed(response)
                }
            )
        } catch {
            req.logger.error("\(error)")
            throw error
        }

        return promise.futureResult
    }

    app.webSocket("runner", ":version", "logs", ":nonce") { (req, ws) in
        guard let nonce = req.parameters.get("nonce") else {
            _ = ws.close()
            return
        }

        let timer = DispatchSource.makeTimerSource()
        timer.setEventHandler {
            guard let path = WorkingDirectoryRegistry.shared.get(prefix: nonce) else { return }

            let completedPath = path.appendingPathComponent("completed")
            let stdoutPath = path.appendingPathComponent("stdout")
            let stderrPath = path.appendingPathComponent("stderr")
            let versionPath = path.appendingPathComponent("version")

            guard let version = (try? String(contentsOf: versionPath)) else { return }

            let stdout = (try? String(contentsOf: stdoutPath)) ?? ""
            let stderr = (try? String(contentsOf: stderrPath)) ?? ""

            let encoder = JSONEncoder()
            if let response = try? String(data: encoder.encode(ExecutionResponse(output: stdout, errors: stderr, version: version)), encoding: .utf8) {
                ws.send(response)
            }

            if let _ = (try? String(contentsOf: completedPath)) {
                timer.cancel()
                _ = ws.close()
            }
        }
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200))
        timer.resume()

        _ = ws.onClose.always { _ in
            timer.cancel()
        }
    }
}

private func installedImageTag() throws -> String {
    let process = Process()
    let standardOutput = Pipe()
    process.standardOutput = standardOutput
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["docker", "images", "--filter=reference=*/swift", "--format", "{{.Tag}}"]
    process.launch()
    process.waitUntilExit()
    let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
        throw Abort(.internalServerError)
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}
