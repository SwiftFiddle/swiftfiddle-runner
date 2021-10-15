import Vapor

func routes(_ app: Application) throws {
    app.get { (req) -> [String: String] in
        return ["status": "pass"]
    }
    
    app.get("runner", ":version", "health") { (req) -> EventLoopFuture<Response> in
        guard let version = req.parameters.get("version") else { throw Abort(.badRequest) }

        let promise = req.eventLoop.makePromise(of: Response.self)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "docker",
            "run",
            "--rm",
            "--pull",
            "missing",
            imageTag(from: version),
            "sh",
            "-c",
            "echo '()' | timeout 10 swiftc -",
        ]
        process.terminationHandler = { (process) in
            let status: HTTPResponseStatus = process.terminationStatus == 0 ? .ok : .internalServerError
            HealthCheckResponse(status: status)
                .encodeResponse(
                    status: status,
                    headers: HTTPHeaders([("Cache-Control", "no-store")]),
                    for: req
                )
                .cascade(to: promise)
        }
        process.launch()

        return promise.futureResult
    }

    app.on(.POST, "runner", ":version", "run", body: .collect(maxSize: "10mb")) { (req) -> EventLoopFuture<ExecutionResponse> in
        guard let version = req.parameters.get("version") else { throw Abort(.badRequest) }
        
        let parameter = try req.content.decode(ExecutionRequestParameter.self)
        let sandboxPath = URL(fileURLWithPath: app.directory.resourcesDirectory).appendingPathComponent("Sandbox")
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
            let response = ExecutionResponse(
                output: stdout,
                errors: fixLineNumber(message: stderr),
                version: version
            )
            if let response = try? String(data: encoder.encode(response), encoding: .utf8) {
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

private struct HealthCheckResponse: Content {
    let status: String

    init(status: HTTPResponseStatus) {
        self.status = status == .ok ? "pass" : "fail"
    }
}
