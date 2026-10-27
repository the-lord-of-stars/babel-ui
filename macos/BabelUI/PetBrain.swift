import Foundation
import Observation
import SwiftUI

enum PetAction: Equatable {
    case idle, hungry, sleep, dance, sing, eat(String), lift, ball, walk, run, held, land, love

    var isMoving: Bool { self == .walk || self == .run }
}

/// Floating decorations: ❤️ ✨ 🎵 💦 💤 …, relative to the crab's feet (y up is negative).
struct Particle {
    var text: String
    var at: CGPoint
    var size: CGFloat = 16
    var opacity: Double = 1
    var rotation: Double = 0
    var color: Color? = nil      // for plain-text particles ("Z", "grr…")
}

/// Decides what the crab does next and where it goes.
@Observable
final class PetBrain {
    static let foods = CrabArt.foods
    static let roamKey = "petRoam"

    private(set) var action: PetAction = .idle
    private(set) var started = Date()
    private(set) var duration: TimeInterval = 3
    /// -1 heading left, +1 heading right.
    private(set) var facing: CGFloat = -1
    @ObservationIgnored var target: CGPoint?

    var roam: Bool {
        get { UserDefaults.standard.object(forKey: Self.roamKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.roamKey) }
    }

    func elapsed(_ now: Date = Date()) -> TimeInterval { now.timeIntervalSince(started) }

    /// `d` is in choreography seconds; at `Choreo.tempo` < 1 everything plays (and lasts) longer.
    func perform(_ a: PetAction, for d: TimeInterval) {
        action = a
        started = Date()
        duration = d / Choreo.tempo
        if !a.isMoving { target = nil }
    }

    func go(to p: CGPoint, from origin: CGPoint, running: Bool) {
        target = p
        facing = p.x < origin.x ? -1 : 1
        perform(running ? .run : .walk, for: 60)
        target = p
    }

    var finished: Bool { !action.isMoving && action != .held && elapsed() >= duration }

    /// Pick the next thing to do. `busy` = GPUs are running.
    func next(busy: Bool, area: CGRect, origin: CGPoint) {
        // Mostly take a breather between acts.
        if action != .idle && Double.random(in: 0..<1) < 0.65 {
            perform(.idle, for: Double.random(in: 4...7))
            return
        }
        var options: [(Double, () -> Void)] = []
        let canRoam = roam && area.width > 0
        if busy {
            options = [
                (2, { self.perform(.dance, for: 6) }),
                (2, { self.perform(.sing, for: 6) }),
                (2, { self.perform(.eat(Self.foods.randomElement()!), for: 5.4) }),
                (2, { self.perform(.lift, for: 6) }),
                (2, { self.perform(.ball, for: 6.4) }),
            ]
            if canRoam {
                options.append((1, { self.go(to: Self.randomPoint(in: area), from: origin, running: true) }))
                options.append((0.8, { self.go(to: Self.randomPoint(in: area), from: origin, running: false) }))
            }
        } else {
            options = [
                (3, { self.perform(.hungry, for: 6) }),
                (1, { self.perform(.sleep, for: 9) }),
                (1, { self.perform(.idle, for: 3) }),
            ]
            if canRoam {
                options.append((1, { self.go(to: Self.randomPoint(in: area), from: origin, running: false) }))
            }
        }
        var roll = Double.random(in: 0..<options.reduce(0) { $0 + $1.0 })
        for (w, act) in options {
            if roll < w { act(); return }
            roll -= w
        }
        options.last?.1()
    }

    static func randomPoint(in area: CGRect) -> CGPoint {
        // Favour the bottom of the screen a bit, but go anywhere.
        let y = Bool.random() ? area.minY + CGFloat.random(in: 0...min(120, area.height)) : CGFloat.random(in: area.minY...area.maxY)
        return CGPoint(x: CGFloat.random(in: area.minX...area.maxX), y: y)
    }
}

/// The animation itself: pose + particles for an action, `τ` seconds into it.
enum Choreo {
    /// Overall animation speed (1 = original, lively; lower = calmer).
    static let tempo = 0.6

    static func pose(_ action: PetAction, τ: Double, t: Double, facing: CGFloat) -> (CrabPose, [Particle]) {
        var p = CrabPose()
        var fx: [Particle] = []
        p.blink = t.truncatingRemainder(dividingBy: 3.3) < 0.13
        let snap = CGFloat(max(0, sin(t * 3))) * 0.25

        /// Particles born every `every` seconds, each living `life` seconds: (index, age 0…1).
        func stream(every: Double, life: Double, _ make: (Int, Double) -> Particle?) {
            let newest = Int(floor(τ / every))
            var k = newest
            while k >= 0 {
                let age = (τ - Double(k) * every) / life
                if age >= 1 { break }
                if age >= 0, let part = make(k, age) { fx.append(part) }
                k -= 1
            }
        }
        func jitter(_ k: Int, _ range: Double) -> Double {
            let h = (k &* 2_654_435_761 &+ 12345) & 0xffff
            return (Double(h) / 65535 * 2 - 1) * range
        }

        switch action {
        case .idle:
            p.squash = 1 + 0.03 * CGFloat(sin(t * 2.2))
            p.look = CGPoint(x: sin(t * 0.7) * 0.9, y: sin(t * 0.45) * 0.4)
            p.mouth = .smile
            p.left.open = 0.25 + snap; p.right.open = 0.25 + snap
            p.left.pos.y += CGFloat(sin(t * 2)) * 2; p.right.pos.y -= CGFloat(sin(t * 2)) * 2

        case .hungry:
            p.eyes = .big
            p.look = CGPoint(x: 0, y: -0.7)
            p.mouth = .open
            p.mouthOpen = 0.85 + 0.15 * CGFloat(sin(τ * 6))
            p.blush = 0.7
            p.left = .init(pos: CGPoint(x: -36, y: 16), dir: 90, open: 0.05)   // hand on the empty tummy
            // Right claw pokes into the huge empty mouth, tap tap tap.
            let cyc = τ.truncatingRemainder(dividingBy: 1.8) / 1.8
            let rest = CGPoint(x: 50, y: -4), poke = CGPoint(x: 13, y: 12)
            let pos: CGPoint
            if cyc < 0.25 { pos = mix(rest, poke, cyc / 0.25) }
            else if cyc < 0.75 { pos = Int((cyc - 0.25) * 12) % 2 == 0 ? poke : CGPoint(x: poke.x + 5, y: poke.y - 2) }
            else { pos = mix(poke, rest, (cyc - 0.75) / 0.25) }
            p.right = .init(pos: pos, dir: 190, open: 0.05)
            // Tummy rumbles.
            let growl = τ.truncatingRemainder(dividingBy: 3.6)
            if growl > 2.8 {
                p.dx = CGFloat(sin(τ * 70)) * 1.6
                fx.append(Particle(text: "grrr~", at: CGPoint(x: -44, y: -22), size: 12, opacity: 0.9, color: CrabArt.line))
            }
            // Dreaming of food.
            let food = PetBrain.foods[Int(τ / 1.8) % PetBrain.foods.count]
            fx.append(Particle(text: "•", at: CGPoint(x: 30, y: -96), size: 10, opacity: 0.85, color: .gray))
            fx.append(Particle(text: "●", at: CGPoint(x: 38, y: -106), size: 12, opacity: 0.85, color: .gray))
            fx.append(Particle(text: "💭", at: CGPoint(x: 54, y: -128), size: 44))
            fx.append(Particle(text: food, at: CGPoint(x: 54, y: -128), size: 20))

        case .sleep:
            p.eyes = .closed
            p.mouth = .o
            p.mouthOpen = 0.05 + 0.08 * CGFloat(sin(τ * 1.6) * 0.5 + 0.5)
            p.squash = 1.04 + 0.04 * CGFloat(sin(τ * 1.6))
            p.left = .init(pos: CGPoint(x: -40, y: 14), dir: 60, open: 0)
            p.right = .init(pos: CGPoint(x: 40, y: 14), dir: 120, open: 0)
            p.blush = 0.6
            stream(every: 1.1, life: 3) { k, a in
                Particle(text: k % 3 == 2 ? "💤" : "Z", at: CGPoint(x: 26 + a * 34 + sin(a * 6) * 6, y: -70 - a * 60),
                         size: CGFloat(12 + a * 12), opacity: 1 - a, color: k % 3 == 2 ? nil : Color(red: 0.4, green: 0.45, blue: 0.85))
            }

        case .dance:
            let beat = τ * 2.6
            let hop = abs(sin(.pi * beat))
            p.lift = CGFloat(hop) * 16
            p.squash = hop < 0.15 ? 1.16 : 0.93
            p.tilt = sin(τ * .pi * 1.3) * 13
            p.eyes = .happy
            p.mouth = .open
            p.mouthOpen = 0.55 + 0.2 * CGFloat(hop)
            p.blush = 0.8
            let up = Int(beat) % 2 == 0
            p.left = .init(pos: CGPoint(x: -50, y: up ? -42 : -10), dir: -110, open: up ? 0.9 : 0.2)
            p.right = .init(pos: CGPoint(x: 50, y: up ? -10 : -42), dir: -70, open: up ? 0.2 : 0.9)
            p.legPhase = τ * 14; p.legAmp = 6
            stream(every: 0.35, life: 1.2) { k, a in
                Particle(text: k % 4 == 0 ? "🎶" : "✨", at: CGPoint(x: jitter(k, 70), y: -60 - jitter(k + 7, 30) - a * 20),
                         size: CGFloat(12 + (1 - abs(a - 0.5) * 2) * 8), opacity: 1 - a, rotation: a * 90)
            }

        case .sing:
            p.eyes = .happy
            p.mouth = .o
            p.mouthOpen = 0.45 + 0.55 * CGFloat(abs(sin(τ * 4)))
            p.tilt = sin(τ * 1.7) * 9
            p.squash = 1 + 0.04 * CGFloat(sin(τ * 8))
            p.blush = 0.85
            p.left = .init(pos: CGPoint(x: -54, y: -40 + CGFloat(sin(τ * 2)) * 6), dir: -120, open: 0.9)   // dramatic!
            p.right = .init(pos: CGPoint(x: 40, y: 16), dir: -90, open: 0.3)
            p.items = [.emoji("🎤", CGPoint(x: 34, y: 6), 22)]
            stream(every: 0.5, life: 2) { k, a in
                Particle(text: k % 2 == 0 ? "🎵" : "🎶", at: CGPoint(x: 18 + a * 60 + jitter(k, 8), y: -30 - a * 70 + sin(a * 9) * 6),
                         size: 18, opacity: 1 - a * a)
            }

        case .eat(let food):
            p.blush = 0.75
            p.left = .init(pos: CGPoint(x: -30, y: 16), dir: -20, open: 0.4)
            p.right = .init(pos: CGPoint(x: 30, y: 16), dir: 200, open: 0.4)
            if τ < 0.8 {                       // !!! food !!!
                p.eyes = .star
                p.mouth = .open; p.mouthOpen = 1
                let a = τ / 0.8
                p.left.pos = mix(CGPoint(x: -50, y: -40), p.left.pos, a)
                p.right.pos = mix(CGPoint(x: 50, y: -40), p.right.pos, a)
                p.items = [.emoji(food, CGPoint(x: 0, y: -46 + 46 * a), 30)]
                p.lift = CGFloat(sin(.pi * a)) * 8
                fx.append(Particle(text: "❗️", at: CGPoint(x: 0, y: -98), size: 20, opacity: 1))
            } else if τ < 4 {                  // CHOMP CHOMP
                let chomp = (τ - 0.8) / 0.5
                let k = Int(chomp)
                let closed = chomp.truncatingRemainder(dividingBy: 1) > 0.55
                p.eyes = closed ? .happy : .normal
                p.look = CGPoint(x: 0, y: 0.6)
                p.mouth = closed ? .cat : .open
                p.mouthOpen = 1
                p.squash = closed ? 1.1 : 0.96
                let left = max(0, 1 - CGFloat(k + (closed ? 1 : 0)) / 6)
                if left > 0 { p.items = [.emoji(food, CGPoint(x: 0, y: closed ? 8 : 2), 30 * left)] }
                stream(every: 0.5, life: 0.7) { j, a in
                    Particle(text: "•", at: CGPoint(x: jitter(j, 24) + jitter(j, 10) * a, y: -20 + a * 28),
                             size: 8, opacity: 1 - a, color: Color(red: 0.75, green: 0.55, blue: 0.25))
                }
                if closed {
                    let side: CGFloat = k % 2 == 0 ? -1 : 1
                    fx.append(Particle(text: "nom!", at: CGPoint(x: side * 64, y: -50 - CGFloat(k % 3) * 8), size: 14,
                                       rotation: Double(side) * 12, color: CrabArt.line))
                }
            } else {                           // so good
                p.eyes = .happy
                p.mouth = .open; p.mouthOpen = 0.45
                p.left = .init(pos: CGPoint(x: -14 + CGFloat(sin(τ * 9)) * 6, y: 18), dir: 90, open: 0.1)   // tummy rub
                p.right = .init(pos: CGPoint(x: 52, y: -30), dir: -60, open: 0.8)
                p.blush = 1
                fx.append(Particle(text: "yum!", at: CGPoint(x: -40, y: -96), size: 15, color: CrabArt.line))
                stream(every: 0.4, life: 1.2) { k, a in
                    Particle(text: "❤️", at: CGPoint(x: 30 + jitter(k, 14), y: -70 - a * 40), size: 14, opacity: 1 - a)
                }
            }

        case .lift:
            let rep = τ / 1.3
            let k = Int(rep)
            let ph = rep - Double(k)
            let up = ph < 0.45 ? ph / 0.45 : (ph < 0.65 ? 1 : 1 - (ph - 0.65) / 0.35)
            let barY = -14 - 52 * CGFloat(up)
            p.items = [.barbell(barY)]
            p.left = .init(pos: CGPoint(x: -40, y: barY + 2), dir: -90, open: 0.25)
            p.right = .init(pos: CGPoint(x: 40, y: barY + 2), dir: -90, open: 0.25)
            p.squash = 1.12 - 0.2 * CGFloat(up)
            p.eyes = ph < 0.45 ? .squeeze : .normal
            p.look = CGPoint(x: 0, y: -1)
            p.mouth = ph < 0.45 ? .grin : .open
            p.mouthOpen = 0.35
            p.blush = 0.5 + 0.5 * up
            p.dx = ph < 0.45 ? CGFloat(sin(τ * 60)) * 1.2 : 0
            if ph > 0.45 && ph < 0.9 {
                let a = (ph - 0.45) / 0.45
                for s in [-1.0, 1.0] {
                    fx.append(Particle(text: "💦", at: CGPoint(x: s * (34 + a * 30), y: -76 + a * 26), size: 14, opacity: 1 - a, rotation: s * 20))
                }
                fx.append(Particle(text: k % 2 == 0 ? "⭐️" : "\(k + 1)!", at: CGPoint(x: 52, y: -110 - a * 10), size: 18,
                                   opacity: 1 - a, color: k % 2 == 0 ? nil : CrabArt.line))
            }

        case .ball:
            let per = 0.75
            let b = τ / per
            let ph = b - floor(b)
            let ballX = CGFloat(sin(τ * 1.4)) * 18
            let ballY = -72 - CGFloat(sin(.pi * ph)) * 58
            p.items = [.emoji("⚽️", CGPoint(x: ballX, y: ballY), 24)]
            p.look = CGPoint(x: ballX / 30, y: -1)
            p.eyes = .normal
            p.mouth = .open; p.mouthOpen = 0.5 + 0.3 * CGFloat(sin(.pi * ph))
            p.lift = ph < 0.18 ? CGFloat(sin(.pi * ph / 0.18)) * 6 : 0
            p.squash = ph < 0.08 || ph > 0.95 ? 1.12 : 1
            p.left = .init(pos: CGPoint(x: -48, y: -34), dir: -110, open: 0.7)
            p.right = .init(pos: CGPoint(x: 48, y: -34), dir: -70, open: 0.7)
            p.legPhase = τ * 10; p.legAmp = 3
            p.blush = 0.7
            if ph < 0.15 { fx.append(Particle(text: "✨", at: CGPoint(x: ballX + 16, y: -74), size: 14, opacity: 1 - ph / 0.15)) }

        case .walk, .run:
            let fast = action == .run
            let speed = fast ? 24.0 : 11.0
            p.legPhase = τ * speed
            p.legAmp = fast ? 8 : 5
            p.lift = CGFloat(abs(sin(τ * speed))) * (fast ? 5 : 2)
            p.tilt = Double(facing) * (fast ? 10 : 4)
            p.look = CGPoint(x: facing * 0.9, y: fast ? -0.1 : sin(t * 1.3) * 0.3)
            p.mouth = fast ? .open : .smile
            p.mouthOpen = fast ? 0.45 + 0.15 * CGFloat(sin(τ * 12)) : 0.4
            let swing = CGFloat(sin(τ * speed)) * (fast ? 12 : 5)
            p.left.pos = CGPoint(x: -50, y: -6 + swing); p.right.pos = CGPoint(x: 50, y: -6 - swing)
            p.left.open = 0.2 + snap; p.right.open = 0.2 + snap
            if fast {
                stream(every: 0.18, life: 0.6) { k, a in
                    Particle(text: "💨", at: CGPoint(x: -facing * (58 + a * 30), y: -6 + jitter(k, 8) - a * 6),
                             size: CGFloat(14 + a * 6), opacity: 1 - a)
                }
            } else if t.truncatingRemainder(dividingBy: 5) < 1.2 {
                fx.append(Particle(text: "♪", at: CGPoint(x: facing * 46, y: -84), size: 14, color: CrabArt.line))
            }

        case .held:
            p.legPhase = τ * 30; p.legAmp = 9
            p.lift = 6
            p.squash = 0.86
            p.tilt = sin(τ * 7) * 9
            p.eyes = .wide
            p.look = CGPoint(x: sin(τ * 9) * 0.6, y: 0.4)
            p.mouth = .o; p.mouthOpen = 0.9
            p.left = .init(pos: CGPoint(x: -52, y: -40 + CGFloat(sin(τ * 20)) * 6), dir: -120, open: 0.9)
            p.right = .init(pos: CGPoint(x: 52, y: -40 - CGFloat(sin(τ * 20)) * 6), dir: -60, open: 0.9)
            fx.append(Particle(text: "‼️", at: CGPoint(x: 0, y: -116), size: 20))
            fx.append(Particle(text: "💦", at: CGPoint(x: 38, y: -84), size: 13, opacity: 0.8))

        case .land:
            p.squash = τ < 0.18 ? 1.32 : 1 + 0.08 * CGFloat(sin(τ * 18) * exp(-τ * 4))
            p.eyes = .dizzy
            p.mouth = .cat
            p.tilt = sin(τ * 5) * 6 * exp(-τ)
            p.left = .init(pos: CGPoint(x: -46, y: 10), dir: 160, open: 0.2)
            p.right = .init(pos: CGPoint(x: 46, y: 10), dir: 20, open: 0.2)
            for i in 0..<3 {
                let a = τ * 4 + Double(i) * 2.1
                fx.append(Particle(text: i == 1 ? "💫" : "⭐️", at: CGPoint(x: cos(a) * 36, y: -86 + sin(a) * 8), size: 12))
            }

        case .love:
            let a = min(τ / 0.6, 1)
            p.lift = CGFloat(sin(.pi * a)) * 24
            p.squash = τ < 0.08 ? 1.2 : (a < 1 ? 0.92 : 1.0 + 0.05 * CGFloat(sin(τ * 10)))
            p.eyes = .heart
            p.mouth = .open; p.mouthOpen = 0.7
            p.blush = 1
            p.left = .init(pos: CGPoint(x: -50, y: -44), dir: -110, open: 0.9)
            p.right = .init(pos: CGPoint(x: 50, y: -44), dir: -70, open: 0.9)
            p.legPhase = τ * 16; p.legAmp = a < 1 ? 6 : 0
            stream(every: 0.22, life: 1.4) { k, age in
                Particle(text: k % 3 == 1 ? "💕" : "❤️", at: CGPoint(x: jitter(k, 46) + sin(age * 8) * 6, y: -60 - age * 60),
                         size: CGFloat(12 + jitter(k + 3, 5)), opacity: 1 - age * age)
            }
        }
        return (p, fx)
    }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint {
        let k = CGFloat(min(max(k, 0), 1))
        return CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }
}
