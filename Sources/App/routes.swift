import Vapor

func routes(_ app: Application) throws {
  app.get { (req) -> [String: String] in
    return ["status": "pass"]
  }

  app.get("runner", ":version", "health") { (req) -> Response in
    guard let version = req.parameters.get("version") else { throw Abort(.badRequest) }

    switch version {
    case "2.2", "2.2.1", "3.0", "3.0.1", "3.0.2", "3.1", "3.1.1",
      "nightly-5.3", "nightly-5.4", "nightly-5.5", "nightly-5.6":
      let status = HTTPResponseStatus.ok
      return try await HealthCheckResponse(status: status)
        .encodeResponse(
          status: status,
          headers: HTTPHeaders([("Cache-Control", "no-store")]),
          for: req
        )
    default:
      break
    }

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

    let status = try await withCheckedThrowingContinuation { (continuation) in
      process.terminationHandler = { (process) in
        let status: HTTPResponseStatus = process.terminationStatus == 0 ? .ok : .internalServerError
        continuation.resume(returning: status)
      }
      do {
        try process.run()
      } catch {
        continuation.resume(throwing: error)
      }
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
    guard let data = req.body.data else { throw Abort(.badRequest) }

    switch version {
    case "nightly-5.3", "nightly-5.4", "nightly-5.5", "nightly-5.6":
      let clientRequest = ClientRequest(
        method: .POST,
        url: URI(
          scheme: .https,
          host: "runner-functions-\(version.split(separator: ".").joined().split(separator: "-").joined()).blackwater-cac8eec1.westus2.azurecontainerapps.io",
          path: "/runner/\(version)/run"
        ),
        headers: HTTPHeaders([("Content-type", "application/json")]),
        body: data
      )

      guard let byteBuffer = try await req.client.send(clientRequest).body else { throw Abort(.internalServerError) }
      guard let response = try byteBuffer.getJSONDecodable(ExecutionResponse.self, at: 0, length: byteBuffer.readableBytes) else {
        throw Abort(.internalServerError)
      }
      return response
    case "2.2", "2.2.1", "3.0", "3.0.1", "3.0.2", "3.1", "3.1.1":
      let clientRequest = ClientRequest(
        method: .POST,
        url: URI(
          scheme: .https,
          host: "swiftfiddle-runner-functions-\(version.split(separator: ".").joined()).blackwater-cac8eec1.westus2.azurecontainerapps.io",
          path: "/runner/\(version)/run"
        ),
        headers: HTTPHeaders([("Content-type", "application/json")]),
        body: data
      )

      guard let byteBuffer = try await req.client.send(clientRequest).body else { throw Abort(.internalServerError) }
      guard let response = try byteBuffer.getJSONDecodable(ExecutionResponse.self, at: 0, length: byteBuffer.readableBytes) else {
        throw Abort(.internalServerError)
      }
      return response
    default:
      break
    }

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
