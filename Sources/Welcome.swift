// Drift — branded launch / setup panel.

import Cocoa
import SwiftUI
import ServiceManagement

enum Brand {
    static let night = Color(red: 0.04, green: 0.06, blue: 0.15)
    static let dusk = Color(red: 0.11, green: 0.12, blue: 0.30)
    static let violet = Color(red: 0.23, green: 0.18, blue: 0.42)
    static let ice = Color(red: 0.56, green: 0.83, blue: 1.0)
    static let frost = Color(red: 0.86, green: 0.93, blue: 1.0)
}

final class WelcomeModel: ObservableObject {
    @Published var effect: Effect = Settings.effect { didSet { Settings.effect = effect; onEffect?() } }
    @Published var intensity: Double = Settings.intensity { didSet { Settings.intensity = intensity } }
    @Published var solidIcons: Bool = Settings.solidIcons { didSet { Settings.solidIcons = solidIcons } }
    @Published var windStrength: Double = Settings.windStrength { didSet { Settings.windStrength = windStrength } }
    @Published var windAngle: Double = Settings.windAngle { didSet { Settings.windAngle = windAngle } }
    @Published var flood: Bool = Settings.flood { didSet { Settings.flood = flood } }
    @Published var axTrusted = AXIsProcessTrusted()
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled

    var onEffect: (() -> Void)?
    var onDone: (() -> Void)?
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = AXIsProcessTrusted()
            if t != self.axTrusted { self.axTrusted = t }
        }
    }
    deinit { timer?.invalidate() }

    func allowAccessibility() {
        DesktopIconTracker.shared.requestAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { NSLog("Drift login item: \(error)") }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Live header preview

struct WeatherPreview: View {
    let effect: Effect

    private func fract(_ v: Double) -> Double { v - floor(v) }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height

                // the little "window" everything lands on
                let win = CGRect(x: w * 0.60, y: h * 0.50, width: w * 0.30, height: h * 0.40)
                let winPath = Path(roundedRect: win, cornerRadius: 10)
                ctx.fill(winPath, with: .color(.white.opacity(0.07)))
                ctx.stroke(winPath, with: .color(.white.opacity(0.18)), lineWidth: 1)
                for (i, c) in [Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                               Color(red: 0.16, green: 0.79, blue: 0.25)].enumerated() {
                    ctx.fill(Path(ellipseIn: CGRect(x: win.minX + 10 + CGFloat(i) * 12, y: win.minY + 9, width: 7, height: 7)),
                             with: .color(c.opacity(0.75)))
                }
                if effect == .snow {
                    var cap = Path()
                    cap.move(to: CGPoint(x: win.minX + 8, y: win.minY))
                    cap.addCurve(to: CGPoint(x: win.maxX - 8, y: win.minY),
                                 control1: CGPoint(x: win.minX + win.width * 0.3, y: win.minY - 13),
                                 control2: CGPoint(x: win.minX + win.width * 0.7, y: win.minY - 9))
                    cap.closeSubpath()
                    ctx.addFilter(.shadow(color: .white.opacity(0.6), radius: 4))
                    ctx.fill(cap, with: .color(Brand.frost))
                }

                var layer = ctx
                layer.addFilter(.blur(radius: 0))
                let n = effect == .rain ? 90 : effect == .fireflies ? 26 : 55
                for i in 0..<n {
                    let s = Double(i) * 0.6180339887
                    let fx = fract(s * 7.31)
                    switch effect {
                    case .snow:
                        let y = fract(t * (0.05 + fract(s * 3.7) * 0.07) + s) * h
                        let x = fx * w + sin(t * 1.2 + s * 9) * 10
                        let r = 1.2 + fract(s * 5.1) * 2.4
                        if win.contains(CGPoint(x: x, y: y)) { continue }
                        layer.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                   with: .color(.white.opacity(0.9)))
                    case .rain:
                        let y = fract(t * (0.7 + fract(s * 3.7) * 0.4) + s) * h
                        let x = fx * w
                        if win.contains(CGPoint(x: x, y: y)) { continue }
                        var p = Path(); p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x - 2, y: y - 14))
                        layer.stroke(p, with: .color(Brand.ice.opacity(0.55)), lineWidth: 1.1)
                    case .sakura, .leaves:
                        let y = fract(t * (0.04 + fract(s * 3.7) * 0.05) + s) * h
                        let x = fx * w + sin(t * 0.9 + s * 9) * 22
                        if win.contains(CGPoint(x: x, y: y)) { continue }
                        let sz = effect == .sakura ? 5.0 : 7.5
                        var c = layer
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .radians(t * 1.5 + s * 6))
                        c.scaleBy(x: 1, y: max(0.25, abs(sin(t * 2 + s * 4))))
                        let col: Color = effect == .sakura
                            ? [Color(red: 1, green: 0.8, blue: 0.86), Color(red: 0.98, green: 0.7, blue: 0.79)][i % 2]
                            : [Color(red: 0.86, green: 0.36, blue: 0.12), Color(red: 0.94, green: 0.56, blue: 0.16),
                               Color(red: 0.95, green: 0.76, blue: 0.27)][i % 3]
                        c.fill(Path(ellipseIn: CGRect(x: -sz, y: -sz * 0.55, width: sz * 2, height: sz * 1.1)), with: .color(col))
                    case .fireflies:
                        let x = (fx + sin(t * 0.21 + s * 5) * 0.06) * w
                        let y = (0.15 + fract(s * 4.3) * 0.75 + cos(t * 0.17 + s * 3) * 0.05) * h
                        let b = pow(0.5 + 0.5 * sin(t * 1.7 + s * 11), 2)
                        let r = 14.0
                        layer.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                   with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.93, blue: 0.55).opacity(0.9 * b),
                                                                           .clear]),
                                                         center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
                    case .storm, .tornado:
                        let y = fract(t * (0.8 + fract(s * 3.7) * 0.4) + s) * h
                        let x = fx * w - y * 0.25
                        if win.contains(CGPoint(x: x, y: y)) { continue }
                        var p = Path(); p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x - 4, y: y - 15))
                        layer.stroke(p, with: .color(Brand.ice.opacity(0.5)), lineWidth: 1.1)
                        if i == 0 && effect == .storm {
                            let k = floor(t / 2.4), ph = fract(t / 2.4)
                            if ph < 0.1 || (ph > 0.14 && ph < 0.2) {
                                var bolt = Path(), bx = (0.15 + fract(k * 0.618) * 0.4) * w, by = 0.0
                                bolt.move(to: CGPoint(x: bx, y: by))
                                var n = 0
                                while by < win.minY - 4 && n < 40 {
                                    by += 12 + fract(Double(n) * 0.73 + k) * 16
                                    bx += (fract(Double(n) * 1.37 + k * 0.3) - 0.5) * 30
                                    bolt.addLine(to: CGPoint(x: bx, y: min(by, win.minY - 2)))
                                    n += 1
                                }
                                layer.stroke(bolt, with: .color(.white), lineWidth: 2)
                                layer.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.white.opacity(0.06)))
                            }
                        }
                        if i == 0 && effect == .tornado {
                            let cx = (fract(t * 0.045) * 1.4 - 0.2) * w
                            for k in 0..<22 {
                                let fy = Double(k) / 21
                                let yy = h * (1 - fy)
                                let r = 6 + fy * fy * 70
                                let xx = cx + sin(t * 1.1 + fy * 4) * 12 * fy - fy * 30
                                let e = Path(ellipseIn: CGRect(x: xx - r, y: yy - r * 0.22, width: r * 2, height: r * 0.44))
                                layer.stroke(e, with: .color(Color(red: 0.75, green: 0.72, blue: 0.68).opacity(0.35)), lineWidth: 1.2)
                            }
                        }
                    case .dust:
                        let x = fract(t * (0.25 + fract(s * 3.7) * 0.25) + s) * w
                        let y = fract(s * 4.1) * h + sin(t * 3 + s * 9) * 6
                        if win.contains(CGPoint(x: x, y: y)) { continue }
                        var p = Path(); p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x - 12, y: y + 1))
                        layer.stroke(p, with: .color(Color(red: 0.88, green: 0.72, blue: 0.5).opacity(0.6)), lineWidth: 1.3)
                    case .starfall:
                        if i % 6 != 0 {
                            let tw = 0.3 + 0.7 * abs(sin(t * 0.8 + s * 13))
                            let r = 0.8
                            layer.fill(Path(ellipseIn: CGRect(x: fx * w - r, y: fract(s * 2.9) * h * 0.9 - r, width: r * 2, height: r * 2)),
                                       with: .color(.white.opacity(0.6 * tw)))
                            continue
                        }
                        let k = fract(t * 0.25 + s)
                        let x = (fx + 0.3) * w - k * w * 0.5, y = k * h
                        var p = Path(); p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + 50, y: y - 50))
                        layer.stroke(p, with: .linearGradient(Gradient(colors: [.white, .clear]),
                                                              startPoint: CGPoint(x: x, y: y),
                                                              endPoint: CGPoint(x: x + 50, y: y - 50)), lineWidth: 1.6)
                    }
                }
            }
        }
    }
}

// MARK: - Panel

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 22) {
                section("Choose your weather") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(Effect.allCases, id: \.self) { e in tile(e) }
                    }
                }
                if model.effect == .snow {
                    HStack(alignment: .top, spacing: 12) {
                        Text("⌥").font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.1)))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.18)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Snowballs and snowmen").font(.system(size: 13, weight: .semibold))
                            Text("Hold Option with the pointer over fallen snow to pack a snowball. Move and let go of Option to throw it. Drop three on top of each other to build a snowman. Throw hard and they burst into snow.")
                                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Brand.ice.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.ice.opacity(0.22)))
                }
                if [.rain, .storm, .tornado].contains(model.effect) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "water.waves").font(.system(size: 16)).foregroundStyle(Brand.ice)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.1)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Flood mode").font(.system(size: 13, weight: .semibold))
                            Text("Rain collects at the bottom of the screen and slowly rises behind your windows. Drain it any time from the menu bar.")
                                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: $model.flood).toggleStyle(.switch).tint(Brand.ice).labelsHidden()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Brand.ice.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.ice.opacity(0.22)))
                }
                section("Intensity & wind") {
                    HStack(alignment: .top, spacing: 22) {
                        VStack(spacing: 4) {
                            HStack {
                                Image(systemName: "cloud.heavyrain").foregroundStyle(Brand.ice)
                                Text("Intensity").font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text(intensityLabel).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                            }
                            Slider(value: $model.intensity, in: 0.5...3.5).tint(Brand.ice)
                        }
                        VStack(spacing: 4) {
                            HStack {
                                Image(systemName: "wind").foregroundStyle(Brand.ice)
                                Text("Strength").font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text(windLabel).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                            }
                            Slider(value: $model.windStrength, in: 0...3).tint(Brand.ice)
                        }
                        VStack(spacing: 4) {
                            HStack {
                                Image(systemName: "arrow.down.right").foregroundStyle(Brand.ice)
                                    .rotationEffect(.degrees(45 - model.windAngle))
                                Text("Angle").font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text(angleLabel).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                                if abs(model.windAngle) > 0.5 {
                                    Button("Reset") { model.windAngle = 0 }.buttonStyle(.plain)
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.ice)
                                }
                            }
                            Slider(value: $model.windAngle, in: -60...60).tint(Brand.ice)
                        }
                    }
                }
                section("Setup") {
                    VStack(spacing: 0) {
                        row(icon: "folder.fill", title: "Desktop files are solid",
                            detail: "Weather lands on your desktop icons too. Needs Accessibility access so Drift can see where icons are.") {
                            if model.axTrusted {
                                Label("Allowed", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
                            } else {
                                Button("Allow…") { model.allowAccessibility() }.buttonStyle(PillButton())
                            }
                        }
                        Divider().overlay(.white.opacity(0.08)).padding(.leading, 44)
                        row(icon: "power", title: "Open at login",
                            detail: "Start Drift automatically when you log in.") {
                            Toggle("", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                                .toggleStyle(.switch).tint(Brand.ice).labelsHidden()
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
                }
                HStack(alignment: .center) {
                    Image(systemName: "menubar.arrow.up.rectangle").foregroundStyle(Brand.ice)
                    Text("Drift lives in your menu bar — click its icon any time to switch weather.")
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button(action: { model.onDone?() }) {
                        Text("Start Drifting").font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 22).padding(.vertical, 10)
                            .background(Capsule().fill(LinearGradient(colors: [Brand.ice, Color(red: 0.62, green: 0.6, blue: 1)],
                                                                       startPoint: .leading, endPoint: .trailing)))
                            .foregroundStyle(Brand.night)
                            .shadow(color: Brand.ice.opacity(0.45), radius: 12)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 24)
        }
        .frame(width: 640)
        .background(LinearGradient(colors: [Brand.dusk, Brand.night], startPoint: .top, endPoint: .bottom))
        .preferredColorScheme(.dark)
    }

    private var intensityLabel: String {
        switch model.intensity {
        case ..<0.8: return "Light"
        case ..<1.6: return "Normal"
        case ..<2.6: return "Heavy"
        default: return "Extreme"
        }
    }

    private var windLabel: String {
        switch model.windStrength {
        case ..<0.25: return "Calm"
        case ..<0.8: return "Breeze"
        case ..<1.5: return "Normal"
        case ..<2.3: return "Strong"
        default: return "Gale"
        }
    }

    private var angleLabel: String {
        let a = Int(model.windAngle.rounded())
        if abs(a) < 1 { return "Straight down" }
        return a < 0 ? "\(-a)° left" : "\(a)° right"
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Brand.violet, Brand.dusk], startPoint: .topTrailing, endPoint: .bottomLeading)
            WeatherPreview(effect: model.effect)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                    Text("Drift").font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, Brand.frost], startPoint: .top, endPoint: .bottom))
                }
                Text("Weather for your desktop that never gets in your way.")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            }
            .padding(28)
        }
        .frame(height: 180)
        .clipped()
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 11, weight: .bold)).kerning(1.2)
                .foregroundStyle(Brand.ice.opacity(0.8))
            content()
        }
    }

    private func tile(_ e: Effect) -> some View {
        let on = model.effect == e
        return Button { model.effect = e } label: {
            HStack(spacing: 10) {
                Image(systemName: e.symbol).font(.system(size: 17, weight: .medium)).frame(width: 22)
                Text(e.title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .foregroundStyle(on ? Brand.night : .white.opacity(0.85))
            .background(RoundedRectangle(cornerRadius: 11)
                .fill(on ? AnyShapeStyle(LinearGradient(colors: [Brand.frost, Brand.ice], startPoint: .topLeading,
                                                        endPoint: .bottomTrailing))
                         : AnyShapeStyle(Color.white.opacity(0.06))))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(on ? .clear : .white.opacity(0.09)))
            .shadow(color: on ? Brand.ice.opacity(0.35) : .clear, radius: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row<A: View>(icon: String, title: String, detail: String, @ViewBuilder accessory: () -> A) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Brand.ice).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            accessory()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

struct PillButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(Brand.ice.opacity(configuration.isPressed ? 0.7 : 1)))
            .foregroundStyle(Brand.night)
    }
}

// MARK: - Window controller

final class WelcomeWindow {
    static var current: NSWindow?

    static func show(onEffect: @escaping () -> Void) {
        if let w = current { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return }
        let model = WelcomeModel()
        model.onEffect = onEffect
        let host = NSHostingView(rootView: WelcomeView(model: model))
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 700),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = host
        w.setContentSize(host.fittingSize)
        w.isReleasedWhenClosed = false
        w.center()
        model.onDone = {
            Settings.onboarded = true
            w.close()
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            Settings.onboarded = true
            current = nil
        }
        current = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
