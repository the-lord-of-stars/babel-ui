import Foundation

/// The GPUs held by the user's running jobs, and roughly what they would cost to rent in a cloud.
/// (Babel itself doesn't bill you — this is just for fun.)
struct GPUUsage: Equatable {
    struct Item: Equatable {
        let type: String
        let count: Int
        /// ≈ $ per GPU-hour.
        let rate: Double
    }

    let items: [Item]
    /// Cost of the running jobs from their start until `fetchedAt`.
    let costAtFetch: Double
    let fetchedAt: Date

    var gpuCount: Int { items.reduce(0) { $0 + $1.count } }
    var perHour: Double { items.reduce(0) { $0 + Double($1.count) * $1.rate } }
    var perSecond: Double { perHour / 3600 }

    /// Total so far, ticking on between polls.
    func total(at now: Date) -> Double {
        costAtFetch + perSecond * max(0, now.timeIntervalSince(fetchedAt))
    }

    /// "2× A6000 + 1× L40S"
    var summary: String {
        items.map { "\($0.count)× \($0.type)" }.joined(separator: " + ")
    }

    /// From /api/queue's jobs: RUNNING jobs whose gres asks for GPUs (per node × nodes).
    static func from(jobs: [(state: String, gres: String, nodes: String, elapsed: String)], at date: Date) -> GPUUsage {
        var counts: [String: Int] = [:]
        var order: [String] = []
        var cost = 0.0
        for job in jobs where job.state == "RUNNING" {
            guard let (type, perNode) = parseGres(job.gres), perNode > 0 else { continue }
            let n = perNode * max(1, Int(job.nodes) ?? 1)
            if counts[type] == nil { order.append(type) }
            counts[type, default: 0] += n
            cost += Double(n) * price(for: type) * parseElapsed(job.elapsed) / 3600
        }
        let items = order.map { Item(type: $0, count: counts[$0]!, rate: price(for: $0)) }
        return GPUUsage(items: items, costAtFetch: cost, fetchedAt: date)
    }

    /// Same rule as server.py's parse_gres: "gres/gpu:A6000:2" → ("A6000", 2), "gpu:2" → ("gpu", 2).
    static func parseGres(_ s: String) -> (String, Int)? {
        guard let m = s.firstMatch(of: /gpu(?::([A-Za-z0-9_.\-]+))?:(\d+)/), let n = Int(m.2) else { return nil }
        return (m.1.map(String.init) ?? "gpu", n)
    }

    /// squeue %M: "M:SS", "H:MM:SS" or "D-HH:MM:SS" → seconds.
    static func parseElapsed(_ s: String) -> Double {
        var days = 0.0
        var rest = Substring(s)
        if let dash = rest.firstIndex(of: "-") {
            days = Double(rest[..<dash]) ?? 0
            rest = rest[rest.index(after: dash)...]
        }
        var secs = 0.0
        for (i, part) in rest.split(separator: ":").reversed().enumerated() {
            secs += (Double(part) ?? 0) * [1, 60, 3600][min(i, 2)]
        }
        return days * 86_400 + secs
    }

    /// ≈ on-demand cloud price per GPU-hour (USD, 2025–26 ballpark). Override one with e.g.
    /// `defaults write local.babel-ui.mac gpuPrices -dict-add l40s 1.2` (key = type, lowercase).
    static func price(for type: String) -> Double {
        let t = type.lowercased()
        if let custom = UserDefaults.standard.dictionary(forKey: "gpuPrices")?[t] {
            if let d = custom as? Double { return d }
            if let s = custom as? String, let d = Double(s) { return d }
        }
        let table: [(String, Double)] = [
            ("h200", 3.50), ("h100", 2.50), ("b200", 5.00),
            ("a100_80", 1.60), ("a100-80", 1.60), ("a100", 1.40),
            ("l40s", 1.00), ("l40", 0.90),
            ("6000ada", 0.80), ("6000_ada", 0.80), ("ada6000", 0.80), ("6000-ada", 0.80),
            ("a6000", 0.50), ("a5000", 0.30), ("a4500", 0.25), ("a4000", 0.20),
            ("a40", 0.45), ("a10", 0.60), ("l4", 0.45),
            ("v100", 0.50), ("p100", 0.30), ("t4", 0.35),
            ("4090", 0.40), ("3090", 0.25), ("2080", 0.15), ("titan", 0.20),
        ]
        return table.first { t.contains($0.0) }?.1 ?? 1.00
    }
}
