import Vapor

func routes(_ app: Application) throws {
    app.get { (req) -> [String: String] in
        return ["status": "pass"]
    }

    app.get("runner", ":version", "health") { (req) -> Response in
        guard let version = req.parameters.get("version") else { throw Abort(.badRequest) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "docker",
            "run",
            "--rm",
            "--pull",
            "never",
            imageTag(from: version),
            "sh",
            "-c",
            "echo '()' | timeout 10 swiftc -",
        ]

        let status: HTTPResponseStatus = try await withCheckedThrowingContinuation { (continuation) in
            process.terminationHandler = { (process) in
                let status: HTTPResponseStatus = process.terminationStatus == 0 ? .ok : .internalServerError
                continuation.resume(returning: status)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
            process.launch()
        }
        return try await HealthCheckResponse(status: status)
            .encodeResponse(
                status: status,
                headers: HTTPHeaders([("Cache-Control", "no-store")]),
                for: req
            )
    }

    app.on(.POST, "runner", ":version", "run", body: .collect(maxSize: "10mb")) { (req) -> ExecutionResponse in
        guard let version = req.parameters.get("version") else { throw Abort(.badRequest) }
        
        let parameter = try req.content.decode(ExecutionRequestParameter.self)
        let sandboxPath = URL(fileURLWithPath: app.directory.resourcesDirectory).appendingPathComponent("Sandbox")
        let runner = Runner( version: version, sandboxPath: sandboxPath)

        return try await runner.run(parameter: parameter)
    }

    app.webSocket("runner", ":version", "logs", ":nonce") { (req, ws) in
        guard let nonce = req.parameters.get("nonce") else {
            _ = ws.close()
            return
        }

        let timer = DispatchSource.makeTimerSource()
        timer.setEventHandler {
            guard let path = WorkingDirectoryRegistry.shared.get(prefix: nonce) else { return }

            let versionPath = path.appendingPathComponent("version")
            let stdoutPath = path.appendingPathComponent("stdout")
            let stderrPath = path.appendingPathComponent("stderr")
            let statusPath = path.appendingPathComponent("status")

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

            if let status = try? String(contentsOf: statusPath), !status.isEmpty {
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

private struct EnvResponse: Content {
    let version: String?
    let images: [String]
}
