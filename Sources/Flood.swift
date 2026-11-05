// Drift — flood mode: rain collects at the bottom of the screen and slowly rises.
// The water is drawn behind every window like everything else, so it never covers your work.

import Cocoa

extension Simulation {
    /// Water surface height at x (local coords), with rolling waves and ripples.
    func waterY(_ x: CGFloat) -> CGFloat {
        let calm = clamp(1 - water / max(1, bounds.height) * 0.3, 0.6, 1)
        let swell = 1 + min(2, windK * stormBoost * 0.4)
        return water
            + 3.2 * swell * calm * sin(x * 0.011 + time * 1.5)
            + 1.8 * swell * sin(x * 0.029 - time * 2.2 + 1.3)
            + 0.9 * sin(x * 0.071 + time * 3.4)
    }

    func stepWater(_ dt: CGFloat) {
        if Settings.flood && rainy {
            let rate: CGFloat = 1.4 * CGFloat(Settings.intensity) * (effect == .rain ? 1 : 1.6)
            water = min(bounds.maxY - 6, max(water, 0) + rate * dt)
        } else if water > -12 {
            water -= dt * 30          // drains away when the rain stops or flood mode is off
        }
        ripples.removeAll { time - $0.t > 1.3 }
    }

    func drainWater() { water = -12; ripples.removeAll() }

    /// Handles a particle at/below the water line. Returns true when the particle was consumed or placed.
    func handleWater(_ p: inout P, py: CGFloat, into out: inout [P]) -> Bool {
        guard water > 0 else { return false }
        let wy = waterY(p.x)
        guard p.y < wy else { return false }
        if rainy && p.hue >= 20 && p.kind == .main {      // leaves, twigs and paper float
            p.y = wy; p.vy = 0; p.vx *= 0.96
            p.rot += sin(time * 2 + p.phase) * 0.01
            if !p.maxLife.isFinite { p.maxLife = p.life + 30 }
            out.append(p)
            return true
        }
        if p.kind == .main && py >= wy - 1 {
            if ripples.count < 90 { ripples.append((x: p.x, t: time)) }
            if CGFloat.random(in: 0...1) < 0.25 {
                out.append(P(x: p.x, y: wy + 1, vx: rnd(-40, 40), vy: rnd(50, 110), size: rnd(0.7, 1.2),
                             maxLife: 0.35, kind: .splash))
            }
        }
        return true                                        // everything else disappears into the water
    }

    func drawWater(_ c: CGContext) {
        guard water > 0 else { return }
        let w = bounds.width
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        var x: CGFloat = 0
        var surface: [CGPoint] = []
        while x <= w + 6 {
            let p = CGPoint(x: x, y: waterY(x)); surface.append(p); path.addLine(to: p)
            x += 6
        }
        path.addLine(to: CGPoint(x: w, y: 0)); path.closeSubpath()

        c.saveGState()
        c.addPath(path); c.clip()
        let storm = effect != .rain
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [CGColor(red: storm ? 0.30 : 0.36, green: storm ? 0.46 : 0.62, blue: storm ? 0.58 : 0.86, alpha: 0.50),
                                    CGColor(red: 0.14, green: 0.30, blue: 0.50, alpha: 0.62),
                                    CGColor(red: 0.05, green: 0.14, blue: 0.28, alpha: 0.78)] as CFArray,
                           locations: [0, 0.35, 1])!
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: water + 6), end: CGPoint(x: 0, y: max(0, water - 500)),
                             options: [.drawsAfterEndLocation])
        // light shafts
        for k in 0..<5 {
            let sx = w * (0.12 + 0.2 * CGFloat(k)) + sin(time * 0.3 + CGFloat(k)) * 40
            c.setFillColor(CGColor(red: 0.8, green: 0.92, blue: 1, alpha: 0.05))
            c.move(to: CGPoint(x: sx - 20, y: water)); c.addLine(to: CGPoint(x: sx + 30, y: water))
            c.addLine(to: CGPoint(x: sx - 60, y: max(0, water - 380))); c.addLine(to: CGPoint(x: sx - 140, y: max(0, water - 380)))
            c.fillPath()
        }
        // bubbles
        c.setStrokeColor(CGColor(red: 0.85, green: 0.95, blue: 1, alpha: 0.35)); c.setLineWidth(1)
        let n = Int(w / 55)
        for k in 0..<n {
            let fk = CGFloat(k)
            let speed = 0.04 + (fk * 0.37).truncatingRemainder(dividingBy: 1) * 0.06
            var fy = (time * speed + fk * 0.13).truncatingRemainder(dividingBy: 1)
            if fy < 0 { fy += 1 }
            let y = fy * water
            let bx = (fk * 0.618).truncatingRemainder(dividingBy: 1) * w + sin(time * 1.3 + fk) * 6
            if y < waterY(bx) - 6 {
                let r = 1.5 + (fk * 0.71).truncatingRemainder(dividingBy: 1) * 2.5
                c.strokeEllipse(in: CGRect(x: bx - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        c.restoreGState()

        // surface highlight
        let line = CGMutablePath(); line.addLines(between: surface)
        c.setStrokeColor(CGColor(red: 0.85, green: 0.95, blue: 1, alpha: 0.55)); c.setLineWidth(1.6)
        c.addPath(line); c.strokePath()
        // ripples where drops land
        c.setLineWidth(1)
        for r in ripples {
            let a = time - r.t
            let rad = 3 + a * 34
            let alpha = max(0, 1 - a / 1.3) * 0.5
            c.setStrokeColor(CGColor(red: 0.9, green: 0.97, blue: 1, alpha: alpha))
            let y = waterY(r.x)
            c.strokeEllipse(in: CGRect(x: r.x - rad, y: y - rad * 0.16, width: rad * 2, height: rad * 0.32))
        }
    }
}
