#if DEBUG
import AppKit
import ImageIO
import SwiftUI
import WebKit

/// Debug-build smoke test, run with BABEL_UI_SELFTEST=<output dir> (see README → Testing).
/// Opens the panel, checks the page, a terminal WebSocket, JS dialogs and (optionally) a
/// download, writes results.json plus screenshots, and quits when BABEL_UI_SELFTEST_QUIT=1.
enum SelfTest {
    static var outDir: URL? {
        ProcessInfo.processInfo.environment["BABEL_UI_SELFTEST"].map { URL(fileURLWithPath: $0) }
    }
    static var isEnabled: Bool { outDir != nil }

    static func run(app: AppDelegate) {
        Task { await runAsync(app: app) }
    }

    /// BABEL_UI_PET_PREVIEW=<dir>: render the crab's acts to GIFs (dance/sing/eat/hungry), then quit.
    static var petPreviewDir: URL? {
        ProcessInfo.processInfo.environment["BABEL_UI_PET_PREVIEW"].map { URL(fileURLWithPath: $0) }
    }

    static func renderPetPreviews(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let busy = GPUUsage(items: [.init(type: "A6000", count: 2, rate: GPUUsage.price(for: "A6000"))],
                            costAtFetch: 1.23, fetchedAt: t0)
        let idle = GPUUsage(items: [], costAtFetch: 0, fetchedAt: t0)
        let acts: [(name: String, action: PetAction, gpu: GPUUsage, secs: Double)] = [
            ("dance", .dance, busy, 3), ("sing", .sing, busy, 3), ("eat", .eat("🍣"), busy, 5.4),
            ("lift", .lift, busy, 3.9), ("ball", .ball, busy, 3), ("run", .run, busy, 1.5),
            ("love", .love, busy, 1.8), ("held", .held, busy, 1.2), ("land", .land, busy, 1.5),
            ("hungry", .hungry, idle, 3.6), ("sleep", .sleep, idle, 3.3), ("walk", .walk, idle, 2),
        ]
        func scene(_ act: (name: String, action: PetAction, gpu: GPUUsage, secs: Double), _ τ: Double) -> some View {
            PetScene(gpu: act.gpu, action: act.action, started: t0, facing: 1, now: t0.addingTimeInterval(τ))
                .background(Color(white: 0.94))
        }
        for act in acts {
            let fps = 20.0
            let count = Int(act.secs * fps)
            let url = dir.appendingPathComponent("crab-\(act.name).gif") as CFURL
            guard let dest = CGImageDestinationCreateWithURL(url, "com.compuserve.gif" as CFString, count, nil) else { continue }
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for i in 0..<count {
                let r = ImageRenderer(content: scene(act, Double(i) / fps))
                r.scale = 1.5
                guard let img = r.cgImage else { continue }
                CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary)
            }
            CGImageDestinationFinalize(dest)
        }
        // Contact sheets: 5 moments per act, one row per act, 4 acts per sheet.
        for (n, chunk) in stride(from: 0, to: acts.count, by: 4).map({ Array(acts[$0..<min($0 + 4, acts.count)]) }).enumerated() {
            let sheet = VStack(spacing: 0) {
                ForEach(chunk.indices, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { k in
                            scene(chunk[row], chunk[row].secs * Double(k) / 5 + 0.05).border(Color.gray.opacity(0.3))
                        }
                    }
                }
            }
            let r = ImageRenderer(content: sheet)
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("sheet\(n + 1).png"))
            }
        }
    }

    private static func runAsync(app: AppDelegate) async {
        let env = ProcessInfo.processInfo.environment
        guard let out = outDir else { return }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var r: [String: Any] = [:]
        var dialogs: [String] = []
        var loaded = false
        app.web.didFinishLoad = { loaded = true }
        app.web.dialogAutoReply = { dialogs.append($0) }

        app.showPanel()
        r["port"] = app.config.port
        r["activationPolicyWhileOpen"] = NSApp.activationPolicy() == .regular ? "regular" : "accessory"

        for _ in 0..<120 {
            if [.running, .unresponsive, .stopped].contains(app.server.phase) { break }
            if case .failed = app.server.phase { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        r["phase"] = String(describing: app.server.phase)
        r["ownsServer"] = app.server.ownsServer
        r["ownedPID"] = app.server.ownedPID.map { Int($0) } ?? NSNull()

        if app.server.phase == .running {
            for _ in 0..<60 where !loaded { try? await Task.sleep(for: .milliseconds(250)) }
            r["pageLoaded"] = loaded
            try? await Task.sleep(for: .seconds(2))
            r["title"] = app.web.webView.title ?? ""

            let js = """
            const r = { secure: window.isSecureContext,
                        clipboardAPI: !!(navigator.clipboard && navigator.clipboard.writeText) };
            r.ws = await new Promise((done) => {
              let got = "", opened = false;
              const ws = new WebSocket(`ws://${location.host}/ws/term`);
              ws.binaryType = "arraybuffer";
              const finish = (why) => { clearTimeout(t); try { ws.close(); } catch (e) {} ;
                                        done({ opened, why, got: got.slice(0, 300) }); };
              const t = setTimeout(() => finish("timeout"), 10000);
              ws.onopen = () => { opened = true; };
              ws.onmessage = (e) => { got += typeof e.data === "string" ? e.data : new TextDecoder().decode(e.data);
                                      if (got.length > 40) finish("data"); };
              ws.onerror = () => finish("error");
              ws.onclose = () => finish("closed");
            });
            r.confirm = confirm("selftest confirm");
            r.prompt = prompt("selftest prompt", "default-text");
            return r;
            """
            do {
                let value = try await app.web.webView.callAsyncJavaScript(js, contentWorld: .page)
                r["js"] = value ?? NSNull()
            } catch {
                r["jsError"] = "\(error)"
            }
            r["dialogs"] = dialogs

            if let path = env["BABEL_UI_SELFTEST_DOWNLOAD"] {
                _ = try? await app.web.webView.evaluateJavaScript("location.href = \(jsString(path)); 0")
                for _ in 0..<60 where app.web.banner == nil { try? await Task.sleep(for: .milliseconds(250)) }
                r["downloadBanner"] = app.web.banner?.text ?? NSNull()
                r["downloadFile"] = app.web.banner?.file?.path ?? NSNull()
                r["downloadFileExists"] = app.web.banner?.file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                try? await Task.sleep(for: .milliseconds(500))
                r["urlAfterDownload"] = app.web.webView.url?.absoluteString ?? NSNull()
            }

            if env["BABEL_UI_SELFTEST_RESTART"] == "1" {
                let before = app.server.ownedPID
                await app.server.restart(includingExternal: false)
                r["restart"] = ["pidBefore": before.map { Int($0) } ?? -1,
                                "pidAfter": app.server.ownedPID.map { Int($0) } ?? -1,
                                "oldPidGone": before.map { kill($0, 0) != 0 } ?? true,
                                "phase": String(describing: app.server.phase)] as [String: Any]
            }

            if env["BABEL_UI_SELFTEST_CLAUDE"] == "1" {
                let js = AppDelegate.claudeTabScript(job: nil, label: "login node")
                r["claudeTab"] = (try? await app.web.webView.evaluateJavaScript(js)) as? String ?? "error"
                try? await Task.sleep(for: .milliseconds(500))
                r["claudeTerms"] = (try? await app.web.webView.evaluateJavaScript(
                    "JSON.stringify(terms.map(t => ({ title: t.base, pending: t.pending, open: t.open })))")) as? String ?? "error"
                r["claudeJobCommand"] = AppDelegate.claudeCommand(job: "12345")
            }

            await app.queue.refresh(server: app.server)
            r["queueSummary"] = app.queue.summary ?? NSNull()
            r["queueDetail"] = app.queue.detail ?? NSNull()

            if let image = try? await app.web.webView.takeSnapshot(configuration: nil) {
                save(image, to: out.appendingPathComponent("web.png"))
            }
        }

        try? await Task.sleep(for: .milliseconds(500))
        if let view = app.window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("window.png"))
        }

        r["petVisible"] = app.pet.isVisible
        r["petAction"] = String(describing: app.pet.brain.action)
        let petMenu = app.petMenu()
        r["petMenu"] = petMenu.items.map { $0.isSeparatorItem ? "---" : $0.title + ($0.isEnabled ? "" : " [disabled]") + ($0.state == .on ? " [on]" : "") }
        if env["BABEL_UI_SELFTEST_ROAM"] == "1", let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }) {
            let before = panel.frame.origin
            app.pet.goForARun()
            try? await Task.sleep(for: .seconds(1.5))
            r["roam"] = ["from": NSStringFromPoint(before), "after1.5s": NSStringFromPoint(panel.frame.origin),
                         "action": String(describing: app.pet.brain.action)]
        }
        r["gpu"] = app.queue.gpu.map { "\($0.summary) · \(dollars($0.perHour))/h · so far \(dollars($0.total(at: Date())))" } ?? NSNull()
        r["visiblePanels"] = NSApp.windows.filter { $0 is NSPanel && $0.isVisible }.map { "\(type(of: $0)) \(NSStringFromRect($0.frame)) content=\(String(describing: $0.contentView.map { type(of: $0) }))" }
        let panel = app.pet.window
        if let view = panel.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("pet.png"))
            r["petFrame"] = NSStringFromRect(panel.frame)
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        app.buildMenu(menu)
        r["menu"] = menu.items.map { item in
            item.isSeparatorItem ? "---"
                : item.title + (item.isEnabled ? "" : " [disabled]") + (item.state == .on ? " [on]" : "")
        }

        app.window?.performClose(nil)
        try? await Task.sleep(for: .milliseconds(300))
        r["activationPolicyAfterClose"] = NSApp.activationPolicy() == .accessory ? "accessory" : "regular"

        if let data = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: out.appendingPathComponent("results.json"))
        }
        if env["BABEL_UI_SELFTEST_QUIT"] == "1" { NSApp.terminate(nil) }
    }

    private static func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        let arr = data.map { String(decoding: $0, as: UTF8.self) } ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())
    }

    private static func save(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
