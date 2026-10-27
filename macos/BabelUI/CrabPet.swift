import SwiftUI

/// "$0.00028": enough decimals to show two significant digits.
func dollars(_ v: Double, minDecimals: Int = 2) -> String {
    guard v > 0 else { return "$0.00" }
    let decimals = max(minDecimals, Int(-floor(log10(v))) + 1)
    return "$" + String(format: "%.\(min(decimals, 8))f", v)
}

/// The whole pet at one moment (pure, so it can also be rendered to images): the crab doing
/// `action`, its little icons, "+$…" cost bubbles while GPUs run, and a caption.
struct PetScene: View {
    static let size = CGSize(width: 240, height: 230)
    static let ground = CGPoint(x: 120, y: 196)

    let gpu: GPUUsage?
    let action: PetAction
    let started: Date
    let facing: CGFloat
    let now: Date

    private var busy: Bool { (gpu?.gpuCount ?? 0) > 0 }

    var body: some View {
        let t = now.timeIntervalSinceReferenceDate
        let τ = max(0, now.timeIntervalSince(started))
        let (pose, fx) = Choreo.pose(action, τ: τ * Choreo.tempo, t: t * Choreo.tempo, facing: facing)
        ZStack(alignment: .top) {
            Canvas { ctx, _ in
                CrabArt.draw(pose, fx, in: ctx, ground: Self.ground)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            if busy, let gpu, action != .held, action != .sleep {
                bubbles(perSecond: gpu.perSecond, t: t, headY: Self.ground.y - 70 - pose.lift)
            }
            if busy, let gpu {
                caption(gpu)
                    .position(x: Self.size.width / 2, y: Self.size.height - 12)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// Every 2 s a "+$…/s" (what one second costs) pops out of the crab's head and drifts away.
    private func bubbles(perSecond: Double, t: Double, headY: CGFloat) -> some View {
        let text = "+" + dollars(perSecond) + "/s"
        let every = 2.0
        let newest = floor(t / every) * every
        return ZStack {
            ForEach(0..<3, id: \.self) { k in
                let born = newest - Double(k) * every
                let age = t - born
                let life = 3.6
                if age >= 0 && age < life {
                    let seed = Int(born / every) &* 2_654_435_761
                    let jitter = Double(abs(seed) % 81) - 40
                    Text(text)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(Color(red: 0.10, green: 0.62, blue: 0.30))
                        .shadow(color: .white, radius: 0, x: 1, y: 1)
                        .shadow(color: .white, radius: 0, x: -1, y: -1)
                        .shadow(color: .black.opacity(0.25), radius: 2)
                        .scaleEffect(age < 0.3 ? 0.4 + age / 0.3 * 0.7 : 1.1 - min(age, 1) * 0.1)
                        .position(x: Self.size.width / 2 + jitter * (0.2 + age / life),
                                  y: headY - 18 - age * 20)
                        .opacity(age < 2.4 ? 1 : 1 - (age - 2.4) / (life - 2.4))
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private func caption(_ gpu: GPUUsage) -> some View {
        Text("\(dollars(gpu.perHour))/h · ≈ \(dollars(gpu.total(at: now))) so far")
            .monospacedDigit()
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.9), in: Rectangle())
            .overlay(Rectangle().strokeBorder(CrabArt.line, lineWidth: 2))
            .help(gpu.summary)
    }
}
