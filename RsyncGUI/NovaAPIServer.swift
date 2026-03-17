//
//  NovaAPIServer.swift
//  RsyncGUI
//
//  Nova/Claude API — port 37424
//
//  Endpoints:
//    GET  /api/status              → app status, job count
//    GET  /api/jobs                → list all sync jobs
//    GET  /api/jobs/:id            → single job detail
//    POST /api/jobs/:id/run        → execute a job
//    POST /api/jobs/:id/dryrun     → dry-run test
//    GET  /api/history             → recent execution history
//    GET  /api/jobs/:id/history    → history for specific job
//
//  Created by Jordan Koch on 2026.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import Foundation
import Network

@MainActor
class NovaAPIServer {
    static let shared = NovaAPIServer()
    let port: UInt16 = 37424
    private var listener: NWListener?
    private let startTime = Date()
    private init() {}

    func start() {
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            listener = try NWListener(using: params)
            listener?.newConnectionHandler = { [weak self] conn in Task { @MainActor in self?.handle(conn) } }
            listener?.stateUpdateHandler = { if case .ready = $0 { print("NovaAPI [RsyncGUI]: port \(self.port)") } }
            listener?.start(queue: .main)
        } catch { print("NovaAPI [RsyncGUI]: failed — \(error)") }
    }
    func stop() { listener?.cancel(); listener = nil }

    private func handle(_ c: NWConnection) { c.start(queue: .main); receive(c, Data()) }
    private func receive(_ c: NWConnection, _ buf: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                var b = buf; if let d = data { b.append(d) }
                if let req = NovaRequest(b) {
                    let resp = await self.route(req)
                    c.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in c.cancel() })
                } else if !done { self.receive(c, b) } else { c.cancel() }
            }
        }
    }

    private func route(_ req: NovaRequest) async -> String {
        if req.method == "OPTIONS" { return http(200, "") }
        let jm = JobManager.shared
        let hm = ExecutionHistoryManager.shared

        switch (req.method, req.path) {

        case ("GET", "/api/status"):
            return json(200, [
                "status": "running", "app": "RsyncGUI", "version": "1.0", "port": "\(port)",
                "jobCount": jm.jobs.count,
                "enabledJobs": jm.jobs.filter { $0.isEnabled }.count,
                "uptimeSeconds": Int(Date().timeIntervalSince(startTime))
            ])

        case ("GET", "/api/ping"):
            return json(200, ["pong": true])

        case ("GET", "/api/jobs"):
            let jobs = jm.jobs.map { j -> [String: Any] in [
                "id": j.id.uuidString,
                "name": j.name,
                "source": j.source,
                "destination": j.destination,
                "isEnabled": j.isEnabled,
                "syncMode": j.syncMode.rawValue
            ]}
            return jsonArray(200, jobs)

        case ("GET", _) where req.path.hasPrefix("/api/jobs/") && !req.path.hasSuffix("/run") && !req.path.hasSuffix("/dryrun") && !req.path.hasSuffix("/history"):
            let idStr = req.path.replacingOccurrences(of: "/api/jobs/", with: "")
            guard let uuid = UUID(uuidString: idStr),
                  let job = jm.jobs.first(where: { $0.id == uuid }) else {
                return json(404, ["error": "Job not found"])
            }
            return json(200, [
                "id": job.id.uuidString, "name": job.name,
                "sources": job.sources, "destination": job.destination,
                "isEnabled": job.isEnabled, "syncMode": job.syncMode.rawValue
            ] as [String: Any])

        case ("POST", _) where req.path.hasSuffix("/run"):
            let idStr = req.path.components(separatedBy: "/").dropLast().last ?? ""
            guard let uuid = UUID(uuidString: idStr),
                  let job = jm.jobs.first(where: { $0.id == uuid }) else {
                return json(404, ["error": "Job not found"])
            }
            Task {
                _ = try? await jm.executeJob(job, dryRun: false)
            }
            return json(200, ["status": "started", "job": job.name])

        case ("POST", _) where req.path.hasSuffix("/dryrun"):
            let idStr = req.path.components(separatedBy: "/").dropLast().last ?? ""
            guard let uuid = UUID(uuidString: idStr),
                  let job = jm.jobs.first(where: { $0.id == uuid }) else {
                return json(404, ["error": "Job not found"])
            }
            Task {
                _ = try? await jm.executeJob(job, dryRun: true)
            }
            return json(200, ["status": "dryrun_started", "job": job.name])

        case ("GET", "/api/history"):
            let entries = hm.getAllHistory(limit: 50).map { e -> [String: Any] in [
                "id": e.id.uuidString,
                "jobName": e.jobName,
                "startTime": ISO8601DateFormatter().string(from: e.timestamp),
                "status": e.status.rawValue,
                "filesTransferred": e.filesTransferred,
                "bytesTransferred": e.bytesTransferred
            ]}
            return jsonArray(200, entries)

        case ("GET", _) where req.path.hasSuffix("/history"):
            let idStr = req.path.components(separatedBy: "/").dropLast().last ?? ""
            guard let uuid = UUID(uuidString: idStr) else { return json(400, ["error": "Invalid UUID"]) }
            let entries = hm.getHistory(for: uuid).map { e -> [String: Any] in [
                "id": e.id.uuidString,
                "startTime": ISO8601DateFormatter().string(from: e.timestamp),
                "status": e.status.rawValue,
                "filesTransferred": e.filesTransferred,
                "bytesTransferred": e.bytesTransferred
            ]}
            return jsonArray(200, entries)

        default:
            return json(404, ["error": "Not found: \(req.method) \(req.path)"])
        }
    }

    private struct NovaRequest {
        let method: String; let path: String; let body: String
        func bodyJSON() -> [String: Any]? { guard let d = body.data(using: .utf8) else { return nil }; return try? JSONSerialization.jsonObject(with: d) as? [String: Any] }
        init?(_ data: Data) {
            guard let raw = String(data: data, encoding: .utf8), raw.contains("\r\n\r\n") else { return nil }
            let parts = raw.components(separatedBy: "\r\n\r\n"); let lines = parts[0].components(separatedBy: "\r\n")
            guard let rl = lines.first else { return nil }; let tokens = rl.components(separatedBy: " "); guard tokens.count >= 2 else { return nil }
            var hdrs: [String: String] = [:]; for l in lines.dropFirst() { let kv = l.components(separatedBy: ": "); if kv.count >= 2 { hdrs[kv[0].lowercased()] = kv.dropFirst().joined(separator: ": ") } }
            let rawBody = parts.dropFirst().joined(separator: "\r\n\r\n")
            if let cl = hdrs["content-length"], let n = Int(cl), rawBody.utf8.count < n { return nil }
            method = tokens[0]; path = tokens[1].components(separatedBy: "?").first ?? tokens[1]; body = rawBody
        }
    }
    private func json(_ s: Int, _ d: [String: Any]) -> String { guard let data = try? JSONSerialization.data(withJSONObject: d, options: .prettyPrinted), let body = String(data: data, encoding: .utf8) else { return http(500, "") }; return http(s, body, "application/json") }
    private func jsonArray(_ s: Int, _ a: [[String: Any]]) -> String { guard let data = try? JSONSerialization.data(withJSONObject: a, options: .prettyPrinted), let body = String(data: data, encoding: .utf8) else { return http(500, "") }; return http(s, body, "application/json") }
    private func http(_ s: Int, _ body: String, _ ct: String = "text/plain") -> String { let st = [200:"OK",201:"Created",400:"Bad Request",404:"Not Found",500:"Internal Server Error"][s] ?? "Unknown"; return "HTTP/1.1 \(s) \(st)\r\nContent-Type: \(ct); charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n\(body)" }
}
