import Foundation
import Observation

/// A one-line summary of the user's Slurm jobs for the menu-bar menu, from GET /api/queue
/// (the same request the panel itself polls; it never prompts, ssh runs with BatchMode).
@Observable
final class QueueMonitor {
    private(set) var summary: String?
    private(set) var detail: String?
    private(set) var updated: Date?
    /// GPUs held by running jobs (nil while the server or the cluster isn't reachable).
    private(set) var gpu: GPUUsage?
    /// Running jobs (for "Ask Claude Code in job …").
    private(set) var running: [RunningJob] = []

    struct RunningJob {
        let id: String
        let name: String
        let gres: String
        let nodes: String   // node list
    }

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var inFlight = false

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30   // the server allows its ssh command 20 s
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    /// Every `interval` seconds: re-check the server, then refresh the summary while it runs.
    func start(server: ServerManager, interval: Duration = .seconds(30)) {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await server.recheck()
                await self?.refresh(server: server)
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Refresh now unless the last answer is fresh enough (used when the menu opens).
    func refreshIfStale(server: ServerManager, maxAge: TimeInterval = 20) {
        if let updated, Date().timeIntervalSince(updated) < maxAge { return }
        Task { await refresh(server: server) }
    }

    func refresh(server: ServerManager) async {
        guard server.phase == .running else {
            summary = nil
            detail = nil
            gpu = nil
            return
        }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let url = server.config.baseURL.appendingPathComponent("api/queue")
        do {
            let (data, _) = try await session.data(from: url)
            let reply = try JSONDecoder().decode(QueueReply.self, from: data)
            if let jobs = reply.jobs {
                gpu = GPUUsage.from(jobs: jobs.map { ($0.state ?? "", $0.gres ?? "", $0.nodes ?? "1", $0.elapsed ?? "0") },
                                    at: Date())
                running = jobs.filter { $0.state == "RUNNING" }.compactMap { j in
                    guard let id = j.id else { return nil }
                    let g = GPUUsage.parseGres(j.gres ?? "").map { "\($0.1)× \($0.0)" } ?? "CPU"
                    return RunningJob(id: id, name: j.name ?? "", gres: g, nodes: j.reason ?? "")
                }
                let states = jobs.map { $0.state ?? "" }
                let running = states.filter { $0 == "RUNNING" }.count
                let pending = states.filter { $0 == "PENDING" }.count
                let other = states.count - running - pending
                if states.isEmpty {
                    summary = "Jobs: none in queue"
                } else {
                    var parts = ["\(running) running", "\(pending) pending"]
                    if other > 0 { parts.append("\(other) other") }
                    summary = "Jobs: " + parts.joined(separator: " · ")
                }
                detail = jobs.prefix(8).map { "\($0.id ?? "?")  \($0.name ?? "")  \($0.state ?? "")" }
                    .joined(separator: "\n")
            } else {
                summary = "Jobs: cluster not connected"
                gpu = nil
                running = []
                detail = reply.error
            }
        } catch {
            summary = "Jobs: unavailable"   // a hiccup: keep the last GPU numbers
            detail = error.localizedDescription
        }
        updated = Date()
    }

    private struct QueueReply: Decodable {
        struct Job: Decodable {
            let id: String?
            let name: String?
            let state: String?
            let gres: String?
            let nodes: String?
            let elapsed: String?
            let reason: String?   // for running jobs: the node list
        }
        let jobs: [Job]?
        let error: String?
    }
}
