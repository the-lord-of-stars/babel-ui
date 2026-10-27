import SwiftUI

/// How the crab looks at one instant. Coordinates are points relative to the body's centre,
/// y pointing down; the feet stand on y = +34 when `lift` is 0. The pixel renderer below snaps
/// all of it to a 4-pt grid.
struct CrabPose {
    enum Eyes { case normal, big, happy, closed, heart, star, squeeze, wide, dizzy }
    enum Mouth { case smile, open, o, grin, cat, flat }
    enum Item {
        case emoji(String, CGPoint, CGFloat)      // something held: food, 🎤, ⚽ … (size shrinks as it's eaten)
        case barbell(CGFloat)                       // bar height (y)
    }
    struct Claw {
        var pos: CGPoint
        var dir: Double        // degrees the pincer opens toward (0 = right, -90 = up)
        var open: CGFloat      // 0 … 1; below 0.12 it's a fist with a pointing finger
    }

    var lift: CGFloat = 0
    var squash: CGFloat = 1          // > 1 wide and flat, < 1 tall and thin
    var tilt: Double = 0             // degrees
    var dx: CGFloat = 0
    var eyes: Eyes = .normal
    var look = CGPoint.zero          // pupils, -1 … 1
    var blink = false
    var mouth: Mouth = .smile
    var mouthOpen: CGFloat = 0.5
    var blush: Double = 0.45
    var left = Claw(pos: CGPoint(x: -50, y: -4), dir: -135, open: 0.3)
    var right = Claw(pos: CGPoint(x: 50, y: -4), dir: -45, open: 0.3)
    var legPhase: Double = 0
    var legAmp: CGFloat = 0
    var items: [Item] = []
}

/// Pixel-art renderer in the style of Claude's little orange mascot: a terracotta block with tall
/// dark eyes, stubby legs and (being a crab) two pincers, every sprite with a 1-px outline.
enum CrabArt {
    static let u: CGFloat = 4                       // points per pixel
    static let cols = Int(PetScene.size.width / u), rows = Int(PetScene.size.height / u)

    static let shell = Color(red: 0.851, green: 0.467, blue: 0.341)    // Claude orange
    static let shellLight = Color(red: 0.95, green: 0.66, blue: 0.53)
    static let shade = Color(red: 0.69, green: 0.34, blue: 0.23)
    static let line = Color(red: 0.36, green: 0.15, blue: 0.10)
    static let ink = Color(red: 0.11, green: 0.09, blue: 0.09)
    static let mouthDark = Color(red: 0.33, green: 0.07, blue: 0.07)
    static let tongue = Color(red: 0.98, green: 0.50, blue: 0.56)
    static let blushPink = Color(red: 1.0, green: 0.50, blue: 0.60)

    static let palette: [Character: Color] = [
        "K": ink, "k": line, "W": .white, "R": Color(red: 0.90, green: 0.16, blue: 0.22),
        "M": Color(red: 1.0, green: 0.45, blue: 0.68), "Y": Color(red: 1.0, green: 0.82, blue: 0.20),
        "O": shell, "o": shellLight, "B": Color(red: 0.45, green: 0.26, blue: 0.14),
        "T": Color(red: 0.86, green: 0.62, blue: 0.33), "C": Color(red: 1.0, green: 0.95, blue: 0.80),
        "G": Color(red: 0.30, green: 0.70, blue: 0.27), "g": Color(red: 0.16, green: 0.45, blue: 0.20),
        "Q": Color(red: 1.0, green: 0.55, blue: 0.40), "S": Color(white: 0.72), "D": Color(white: 0.30),
        "b": Color(red: 0.32, green: 0.55, blue: 0.95), "L": Color(red: 0.62, green: 0.84, blue: 1.0),
        "P": blushPink,
    ]

    // MARK: Sprites ("." = clear)

    static let sprites: [String: (rows: [String], outline: Bool)] = [
        "❤️": ([".RR.RR.", "RRRRRRR", "RWRRRRR", ".RRRRR.", "..RRR..", "...R..."], true),
        "💕": (["MM.MM", "MMMMM", ".MMM.", "..M.."], true),
        "eye♥": (["RR.RR", "RRRRR", ".RRR.", "..R.."], false),
        "✨": (["..Y..", "..Y..", "YYWYY", "..Y..", "..Y.."], false),
        "⭐️": (["..Y..", ".YYY.", "YYYYY", ".YYY.", ".Y.Y."], true),
        "💫": (["..Y..", ".YWY.", "..Y.."], false),
        "🎵": (["..KKK", "..K..", "..K..", "KKK..", "KKK.."], false),
        "🎶": ([".KKKKK", ".K...K", ".K...K", "KK..KK", "KK..KK"], false),
        "♪": (["..KK", "..K.", "KKK.", "KK.."], false),
        "💦": (["..b", ".bb", "bLb", "bbb", ".b."], false),
        "Z": (["bbbbb", "...b.", "..b..", ".b...", "bbbbb"], false),
        "💤": (["bbbbbb", "....b.", "...b..", "..b...", ".b....", "bbbbbb"], false),
        "💨": (["..SS...", ".SWWS..", "SWWWWSS", ".SSSSS."], false),
        "❗️": (["RR", "RR", "RR", "RR", "..", "RR"], true),
        "‼️": (["RR.RR", "RR.RR", "RR.RR", "RR.RR", ".....", "RR.RR"], true),
        "💭": (["....WWWWWWW....", "..WWWWWWWWWWW..", ".WWWWWWWWWWWWW.", "WWWWWWWWWWWWWWW", "WWWWWWWWWWWWWWW",
                "WWWWWWWWWWWWWWW", "WWWWWWWWWWWWWWW", ".WWWWWWWWWWWWW.", "..WWWWWWWWWWW..", "....WWWWWWW...."], true),
        "•": (["W"], true),
        "●": (["WW", "WW"], true),
        "🎤": ([".DDD.", "DSSSD", "DSSSD", ".DDD.", "..K..", "..K..", "..K.."], true),
        "⚽️": ([".WWWW.", "WWKKWW", "WKKKKW", "WWKKWW", "KWWWWK", ".WKKW."], true),
        // Food.
        "🍔": (["..TTTT..", ".TCTTCT.", "TTTTTTTT", "GgGGgGGG", "BBBBBBBB", "YYYYYYYY", ".TTTTTT."], true),
        "🍣": (["..QQQQ..", ".QWQQWQQ", "QQQQQQQQ", "WWWWWWWW", "WWWWWWWW", ".WWWWWW."], true),
        "🍕": (["TTTTTTTT", "YRYYYRYY", ".YYYRYY.", "..YRYY..", "..YYY...", "...Y...."], true),
        "🍩": (["..MMMM..", ".MWMMYM.", "MMM..MMM", "TTT..TTT", ".TTTTTT.", "..TTTT.."], true),
        "🍉": (["RRKRRKRR", "RRRRRRRR", ".RRKRRR.", "..WWWW..", "...GG..."], true),
        "🍙": (["...WW...", "..WWWW..", ".WWWWWW.", "WWWWWWWW", "WWKKKKWW", "WWKKKKWW"], true),
        "🍪": ([".TTTTT.", "TTBTTTT", "TTTTBTT", "TBTTTTT", "TTTTBTT", ".TTTTT."], true),
        "🍦": (["..WWW..", ".WWWWW.", "WWWWWWW", ".TTTTT.", "..TBT..", "..TTT..", "...T..."], true),
    ]
    static let foods = ["🍔", "🍣", "🍕", "🍩", "🍉", "🍙", "🍪", "🍦"]

    // MARK: Pixel buffer

    private struct Pix {
        var px: [Int: Color] = [:]
        /// Tilt, done pixel-style: rows above `shearMid` slide sideways by `shift` as one block.
        var shift = 0
        var shearMid = 0

        mutating func put(_ x: Int, _ y: Int, _ c: Color) {
            let sx = x + (y < shearMid ? shift : 0)
            guard sx >= 0, sx < CrabArt.cols, y >= 0, y < CrabArt.rows else { return }
            px[y * CrabArt.cols + sx] = c
        }
        mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: Color) {
            guard w > 0, h > 0 else { return }
            for yy in y..<(y + h) { for xx in x..<(x + w) { put(xx, yy, c) } }
        }
        mutating func line(_ a: (Int, Int), _ b: (Int, Int), _ c: Color) {
            var (x0, y0) = a
            let (x1, y1) = b
            let dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1
            let dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1
            var err = dx + dy
            while true {
                put(x0, y0, c)
                if x0 == x1 && y0 == y1 { break }
                let e2 = 2 * err
                if e2 >= dy { err += dy; x0 += sx }
                if e2 <= dx { err += dx; y0 += sy }
            }
        }
        /// Cells drawn with a 1-px outline around them (outline first, so it never covers them).
        mutating func outlined(_ cells: [(Int, Int, Color)], _ outline: Color = CrabArt.line) {
            let set = Set(cells.map { $0.1 * 10_000 + $0.0 })
            for (x, y, _) in cells {
                for (ox, oy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] where !set.contains((y + oy) * 10_000 + x + ox) {
                    put(x + ox, y + oy, outline)
                }
            }
            for (x, y, c) in cells { put(x, y, c) }
        }
        /// A sprite centred on (cx, cy). `keep` < 1 hides columns from the left (bitten food).
        mutating func sprite(_ name: String, _ cx: Int, _ cy: Int, keep: Double = 1, alpha: Double = 1) {
            guard let s = CrabArt.sprites[name] else { return }
            let w = s.rows.map(\.count).max() ?? 0, h = s.rows.count
            let firstCol = Int((Double(w) * (1 - keep)).rounded())
            var cells: [(Int, Int, Color)] = []
            for (r, row) in s.rows.enumerated() {
                for (c, ch) in row.enumerated() where c >= firstCol {
                    if let col = CrabArt.palette[ch] { cells.append((cx - w / 2 + c, cy - h / 2 + r, col.opacity(alpha))) }
                }
            }
            if s.outline { outlined(cells, CrabArt.line.opacity(alpha)) } else { cells.forEach { put($0.0, $0.1, $0.2) } }
        }
    }

    // MARK: Drawing

    /// Draws the crab and its particles with its feet's centre at `ground` (canvas coordinates).
    static func draw(_ pose: CrabPose, _ fx: [Particle], in ctx: GraphicsContext, ground: CGPoint) {
        var p = Pix()
        let gx = Int(ground.x / u), gy = Int(ground.y / u)       // ground cell (feet stand on gy - 1)
        let lift = Int((pose.lift / u).rounded())
        let bw = max(12, Int((18 * pose.squash / 2).rounded()) * 2)
        let bh = max(8, Int((11 / pose.squash).rounded()))
        let cx = gx + Int((pose.dx / u).rounded())
        let bottom = gy - 4 - lift
        let top = bottom - bh + 1
        let left = cx - bw / 2, right = left + bw - 1
        let mid = (top + bottom) / 2
        func cell(_ pt: CGPoint) -> (Int, Int) { (cx + Int((pt.x / u * 0.9).rounded()), mid + Int((pt.y / u).rounded())) }

        // Shadow on the ground, smaller when airborne.
        let sw = max(6, bw - lift)
        p.rect(cx - sw / 2, gy, sw, 1, .black.opacity(0.18))

        let lean = Int((tan(pose.tilt * .pi / 180) * Double(bh) / 2).rounded())
        p.shearMid = mid

        // Legs: three a side, stepping when walking, dangling when airborne.
        for (i, lx) in [left + 1, left + 3, left + 5, right - 5, right - 3, right - 1].enumerated() {
            let phase = pose.legPhase + Double(i % 3) * 2.1 + (i >= 3 ? .pi : 0)
            let up = pose.legAmp > 0 && sin(phase) > 0.25 ? 1 : 0
            let len = 3 - up
            var cells: [(Int, Int, Color)] = []
            for y in (bottom + 1)...(bottom + len) { cells.append((lx, y, shade)) }
            let foot = i < 3 ? lx - 1 : lx + 1
            if i == 0 || i == 5 { cells.append((foot, bottom + len, shade)) }
            p.outlined(cells)
        }

        // Arms (behind the body).
        for claw in [pose.left, pose.right] {
            let c = cell(claw.pos)
            let shoulder = (claw.pos.x < 0 ? left - 1 : right + 1, mid + 1)
            p.line(shoulder, c, line)
            p.line((shoulder.0, shoulder.1 - 1), (c.0, c.1 - 1), shade)
        }

        p.shift = lean
        // Body: the block, outlined, rounded corners, a shine and a darker belly line.
        var body: [(Int, Int, Color)] = []
        for y in top...bottom {
            for x in left...right {
                let corner = (y == top || y == bottom) && (x == left || x == right)
                if !corner { body.append((x, y, y == bottom ? shade : shell)) }
            }
        }
        p.outlined(body)
        p.rect(left + 2, top + 1, 3, 1, shellLight)
        p.put(left + 1, top + 2, shellLight)

        // Cheeks.
        if pose.blush > 0.3 {
            let pink = blushPink.opacity(min(1, pose.blush + 0.2))
            p.rect(left + 1, top + 6, 2, 1, pink)
            p.rect(right - 2, top + 6, 2, 1, pink)
        }

        drawMouth(pose, &p, cx: cx, row: top + 6, bottom: bottom)
        drawEyes(pose, &p, cx: cx, row: top + 2)

        // Held things, then the claws holding them.
        p.shift = 0
        for item in pose.items {
            switch item {
            case .emoji(let s, let pt, let size):
                let (x, y) = cell(pt)
                let keep = Double(size) / (s == "🎤" ? 22 : s == "⚽️" ? 24 : 30)
                if keep > 0.08 { p.sprite(s, x, y, keep: min(1, keep)) }
            case .barbell(let by):
                let y = mid + Int((by / u).rounded())
                p.outlined((cx - 17...cx + 16).map { ($0, y, Color(white: 0.72)) })
                for s in [-1, 1] {
                    let px = s < 0 ? cx - 16 : cx + 14
                    var plate: [(Int, Int, Color)] = []
                    for yy in (y - 3)...(y + 3) { plate.append((px, yy, Color(white: 0.25))); plate.append((px + 1, yy, Color(white: 0.25))) }
                    p.outlined(plate)
                }
            }
        }
        for claw in [pose.left, pose.right] { drawClaw(claw, &p, at: cell(claw.pos)) }

        // Particles: pixel sprites where we have one, otherwise chunky monospaced text.
        var texts: [(Particle, CGPoint)] = []
        for f in fx {
            let x = gx + Int((f.at.x / u).rounded()), y = gy + Int((f.at.y / u).rounded())
            if sprites[f.text] != nil {
                p.sprite(f.text, x, y, alpha: f.opacity)
            } else {
                texts.append((f, CGPoint(x: CGFloat(x) * u, y: CGFloat(y) * u)))
            }
        }

        for (key, color) in p.px {
            let x = key % cols, y = key / cols
            ctx.fill(Path(CGRect(x: CGFloat(x) * u, y: CGFloat(y) * u, width: u, height: u)), with: .color(color))
        }
        for (f, pt) in texts {
            var c = ctx
            c.opacity = f.opacity
            c.translateBy(x: pt.x, y: pt.y)
            c.rotate(by: .degrees(f.rotation))
            c.draw(Text(f.text).font(.system(size: f.size, weight: .black, design: .monospaced))
                    .foregroundColor(f.color ?? line), at: .zero, anchor: .center)
        }
    }

    private static func drawClaw(_ claw: CrabPose.Claw, _ p: inout Pix, at c: (Int, Int)) {
        let (x, y) = c
        var d = claw.dir.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        let rows: [String]
        if claw.open < 0.12 {   // fist + pointing finger
            let fist: [(Int, Int)] = [(0, 0), (1, 0), (0, 1), (1, 1)]
            let step: (Int, Int) = abs(d) <= 45 ? (1, 0) : (abs(d) >= 135 ? (-1, 0) : (d < 0 ? (0, -1) : (0, 1)))
            let base = step.0 > 0 ? (2, 0) : step.0 < 0 ? (-1, 0) : step.1 < 0 ? (0, -1) : (0, 2)
            var cells = fist.map { (x + $0.0, y + $0.1, shellLight) }
            cells.append((x + base.0, y + base.1, shellLight))
            cells.append((x + base.0 + step.0, y + base.1 + step.1, shellLight))
            p.outlined(cells)
            return
        }
        if claw.open < 0.45 {
            rows = ["XXX", "XXX", ".X."]
        } else if d > -135 && d < -45 {
            rows = ["X.X", "XXX", ".X."]          // opens up
        } else if d > 45 && d < 135 {
            rows = [".X.", "XXX", "X.X"]          // opens down
        } else if abs(d) <= 45 {
            rows = [".XX", "XX.", ".XX"]          // opens right
        } else {
            rows = ["XX.", ".XX", "XX."]          // opens left
        }
        var cells: [(Int, Int, Color)] = []
        for (r, row) in rows.enumerated() {
            for (k, ch) in row.enumerated() where ch == "X" { cells.append((x - 1 + k, y - 1 + r, shellLight)) }
        }
        p.outlined(cells)
    }

    private static func drawMouth(_ pose: CrabPose, _ p: inout Pix, cx: Int, row: Int, bottom: Int) {
        let o = pose.mouthOpen
        switch pose.mouth {
        case .smile:
            p.put(cx - 3, row, ink); p.put(cx + 2, row, ink)
            p.rect(cx - 2, row + 1, 4, 1, ink)
        case .open:
            // The big one: up to 10 px wide and 5 deep, reaching the belly.
            let w = 4 + 2 * Int((3 * o).rounded())
            let h = 1 + Int((4 * o).rounded())
            p.rect(cx - w / 2, row, w, h, mouthDark)
            p.put(cx - w / 2, row + h - 1, shell); p.put(cx + w / 2 - 1, row + h - 1, shell)   // rounder
            if h >= 2 { p.rect(cx - w / 2 + 1, row + h - 1, w - 2, 1, tongue) }
            if h >= 3 { p.put(cx - 1, row, .white); p.put(cx, row, .white) }                    // buck teeth
        case .o:
            let w = 2 + 2 * Int(o.rounded())
            let h = 2 + Int((2 * o).rounded())
            p.rect(cx - w / 2, row, w, h, mouthDark)
            if w >= 4 && h >= 3 {
                for (x, y) in [(cx - w / 2, row), (cx + w / 2 - 1, row), (cx - w / 2, row + h - 1), (cx + w / 2 - 1, row + h - 1)] {
                    p.put(x, y, shell)
                }
                p.rect(cx - 1, row + h - 1, 2, 1, tongue)
            }
        case .grin:
            var cells: [(Int, Int, Color)] = []
            for x in (cx - 4)...(cx + 3) {
                for y in row...(row + 1) { cells.append((x, y, (x - cx) % 2 == 0 && y == row ? Color(white: 0.85) : .white)) }
            }
            p.outlined(cells, ink)
        case .cat:
            for (dx, dy) in [(-3, 0), (-2, 1), (-1, 0), (0, 0), (1, 1), (2, 0)] { p.put(cx + dx, row + dy, ink) }
        case .flat:
            p.rect(cx - 2, row + 1, 4, 1, ink)
        }
    }

    private static func drawEyes(_ pose: CrabPose, _ p: inout Pix, cx: Int, row: Int) {
        let lx = Int(pose.look.x.rounded()), ly = Int(pose.look.y.rounded())
        for side in [-1, 1] {
            let ex = side < 0 ? cx - 5 : cx + 3          // left column of a 2-wide eye
            if pose.blink && [.normal, .big, .wide].contains(pose.eyes) {
                p.rect(ex, row + 2, 2, 1, ink)
                continue
            }
            switch pose.eyes {
            case .normal:      // Claude's tall eyes
                p.rect(ex + max(0, lx) - (lx < 0 ? 1 : 0), row + ly, 2, 3, ink)
            case .big:         // huge pleading eyes with sparkles and a tear line
                p.rect(ex - 1, row - 1, 4, 4, ink)
                p.put(ex - 1, row - 1, .white); p.put(ex, row - 1, .white); p.put(ex - 1, row, .white)
                p.put(ex + 2, row + 2, .white)
                p.rect(ex - 1, row + 3, 4, 1, Color(red: 0.55, green: 0.80, blue: 1.0))
            case .wide:        // shocked
                p.outlined([(ex, row, .white), (ex + 1, row, .white), (ex, row + 1, .white), (ex + 1, row + 1, ink),
                            (ex, row + 2, .white), (ex + 1, row + 2, .white)], ink)
            case .happy:       // ^ ^
                p.put(ex - 1, row + 2, ink); p.put(ex, row + 1, ink); p.put(ex + 1, row + 1, ink); p.put(ex + 2, row + 2, ink)
            case .closed:      // sleepy — lids and lashes
                p.rect(ex - 1, row + 2, 4, 1, ink)
                p.put(ex - 1, row + 3, ink); p.put(ex + 2, row + 3, ink)
            case .heart:
                p.sprite("eye♥", ex + 1, row + 1)
            case .star:
                p.sprite("⭐️", ex + 1, row + 1)
            case .squeeze:     // > <
                let d = side < 0 ? 1 : -1
                p.put(ex + (d > 0 ? -1 : 2), row, ink); p.put(ex + (d > 0 ? 0 : 1), row + 1, ink)
                p.put(ex + (d > 0 ? 1 : 0), row + 2, ink); p.put(ex + (d > 0 ? 0 : 1), row + 3, ink)
                p.put(ex + (d > 0 ? -1 : 2), row + 4, ink)
            case .dizzy:       // little spirals
                for (dx, dy) in [(-1, 0), (0, 0), (1, 0), (2, 0), (2, 1), (2, 2), (1, 2), (0, 2), (0, 1)] {
                    p.put(ex + dx, row + dy, ink)
                }
                p.put(ex + 1, row + 1, .white)
            }
        }
    }
}
