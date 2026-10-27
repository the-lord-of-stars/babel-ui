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

    /// ≈ on-demand cloud price per GPU-hour (USD). Reference: RunPod Secure Cloud and Lambda list
    /// prices, Oct 2026 — neocloud rates, not AWS/GCP/Azure (those run 2–4× higher for the big cards).
    /// Types marked "rough" had no current listing. Override one with e.g.
    /// `defaults write local.babel-ui.mac gpuPrices -dict-add l40s 1.2` (key = type, lowercase).
    static func price(for type: String) -> Double {
        let t = type.lowercased()
        if let custom = UserDefaults.standard.dictionary(forKey: "gpuPrices")?[t] {
            if let d = custom as? Double { return d }
            if let s = custom as? String, let d = Double(s) { return d }
        }
        let table: [(String, Double)] = [
            ("b200", 6.70),                                   // Lambda
            ("h200", 3.60),                                   // rough
            ("h100", 2.90),                                   // RunPod 2.89, Lambda 2.99
            ("a100_80", 1.50), ("a100-80", 1.50), ("a100_40", 1.20), ("a100-40", 1.20),
            ("a100", 1.40),                                   // RunPod 1.39, Lambda 1.99
            ("l40s", 1.05),                                   // RunPod 1.09
            ("l40", 0.82),                                    // RunPod
            ("6000ada", 0.99), ("6000_ada", 0.99), ("ada6000", 0.99), ("6000-ada", 0.99),   // RunPod
            ("a6000", 0.60),                                  // RunPod 0.59
            ("a5000", 0.27), ("a4500", 0.25), ("a4000", 0.20),   // RunPod / rough
            ("a40", 0.59),                                    // RunPod
            ("a10", 0.86),                                    // Lambda
            ("l4", 0.59),                                     // RunPod
            ("v100", 0.50), ("p100", 0.30), ("t4", 0.35),     // rough
            ("4090", 0.89), ("3090", 0.50), ("2080", 0.15), ("titan", 0.20),
        ].sorted { $0.0.count > $1.0.count }                  // most specific name wins
        return table.first { t.contains($0.0) }?.1 ?? 1.00
    }
}
