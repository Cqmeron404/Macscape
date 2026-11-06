// Macscapes — flood mode: rain collects at the bottom of the screen and slowly rises.
// The water is drawn behind every window like everything else, so it never covers your work.

import Cocoa

/// A fish or jellyfish that lives in the flood water.
struct Fish {
    var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat = 0
    var size: CGFloat
    var hue: Int           // body colour
    var phase: CGFloat
    var kind: Int          // 0 = fish, 1 = jellyfish
    var entered = false    // false while still swimming in from a side / up from the bottom
    var dir: CGFloat { vx >= 0 ? 1 : -1 }
}

/// A sailboat that drifts across the flood water; a click breaks it and it sinks.
struct Boat {
    var x: CGFloat
    var vx: CGFloat
    var hue: Int
    var phase: CGFloat
    var size: CGFloat
    var sinking: CGFloat = -1   // < 0 sailing; >= 0 seconds since it was hit
}

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
            // Fill from the rain volume: slower overall, and it eases off as the pool deepens
            // (a given downpour raises a near-full screen far less than an empty one).
            let fill = 0.55 * CGFloat(Settings.intensity) * (effect == .rain ? 1 : 1.5)
            let ease = clamp(1 - water / (bounds.height * 0.9), 0.12, 1)
            water = min(bounds.maxY - 6, max(water, 0) + fill * ease * dt)
        } else if water > -12 {
            water -= dt * 30          // drains away when the rain stops or flood mode is off
        }
        ripples.removeAll { time - $0.t > 1.3 }
        stepFish(dt)
    }

    func drainWater() { water = -12; ripples.removeAll(); fish.removeAll(); boat = nil }

    // MARK: fish & sea creatures

    func stepFish(_ dt: CGFloat) {
        let depth = water - groundY
        guard water > 0, depth > 36 else { if !fish.isEmpty { fish.removeAll() }; return }
        let target = min(14, max(1, Int(depth * bounds.width / 90000)))

        // Let them swim in one at a time rather than popping into existence.
        if fish.count < target {
            fishAcc += dt
            if fishAcc > 0.7 {
                fishAcc = 0
                if Int.random(in: 0...4) == 0 {                 // a jellyfish rises up from the bottom
                    let s = rnd(9, 16)
                    fish.append(Fish(x: rnd(s, bounds.width - s), y: groundY + s * 0.6,
                                     vx: 0, vy: rnd(45, 95), size: s,
                                     hue: Int.random(in: 0...3), phase: rnd(0, .pi * 2), kind: 1))
                } else {                                        // a fish swims in from a side
                    let s = rnd(6, 15)
                    let fromLeft = Bool.random()
                    fish.append(Fish(x: fromLeft ? -s - 6 : bounds.width + s + 6,
                                     y: rnd(groundY + 14, max(groundY + 16, water - 18)),
                                     vx: (fromLeft ? 1 : -1) * rnd(22, 48), size: s,
                                     hue: Int.random(in: 0...3), phase: rnd(0, .pi * 2), kind: 0))
                }
            }
        }
        while fish.count > target + 2 { fish.removeFirst() }

        for i in fish.indices {
            var f = fish[i]
            if f.kind == 0 {                                  // fish swim side to side
                f.x += f.vx * dt
                f.y += sin(time * 2 + f.phase) * 8 * dt
                if f.entered {
                    if f.x < f.size { f.x = f.size; f.vx = abs(f.vx) }
                    if f.x > bounds.width - f.size { f.x = bounds.width - f.size; f.vx = -abs(f.vx) }
                    if CGFloat.random(in: 0...1) < dt * 0.18 { f.vx = -f.vx }   // occasional turn
                } else if f.x > f.size && f.x < bounds.width - f.size {
                    f.entered = true                          // fully on-screen now; start patrolling
                }
            } else {                                          // jellyfish rise, then bob and drift
                if !f.entered {
                    f.y += f.vy * dt
                    f.vy *= 1 - 0.7 * dt
                    f.x += sin(time * 0.5 + f.phase) * 8 * dt
                    if f.vy < 14 { f.entered = true }
                } else {
                    f.y += sin(time * 1.1 + f.phase) * 16 * dt
                    f.x += sin(time * 0.5 + f.phase * 1.3) * 12 * dt
                }
                f.x = clamp(f.x, f.size, bounds.width - f.size)
            }
            let top = waterY(f.x) - f.size * 0.9, bot = groundY + f.size * 0.6
            if f.y > top { f.y = top }
            if f.y < bot { f.y = bot }
            fish[i] = f
        }
        stepBoat(dt)
    }

    // MARK: sailboat

    func stepBoat(_ dt: CGFloat) {
        guard water > 0, water - groundY > 70 else { boat = nil; return }
        if var b = boat {
            if b.sinking >= 0 {                               // broken: sink, bubble, then vanish
                b.sinking += dt
                if b.sinking > 0.2, ripples.count < 90, CGFloat.random(in: 0...1) < dt * 10 {
                    ripples.append((x: b.x + rnd(-b.size, b.size), t: time))
                }
                if b.sinking > 4 { boat = nil; nextBoat = rnd(12, 30); return }
                boat = b
            } else {                                          // sailing across
                b.x += b.vx * dt
                if (b.vx > 0 && b.x > bounds.width + b.size * 2) || (b.vx < 0 && b.x < -b.size * 2) {
                    boat = nil; nextBoat = rnd(10, 22); return
                }
                boat = b
            }
        } else {
            nextBoat -= dt
            if nextBoat <= 0 {
                let s = rnd(26, 40)
                let fromLeft = Bool.random()
                boat = Boat(x: fromLeft ? -s : bounds.width + s,
                            vx: (fromLeft ? 1 : -1) * rnd(14, 26),
                            hue: Int.random(in: 0...3), phase: rnd(0, .pi * 2), size: s)
            }
        }
    }

    /// A left-click (seen via a global monitor) that lands on the boat breaks it.
    func clickAt(global: CGPoint) {
        guard var b = boat, b.sinking < 0, water > 0 else { return }
        let p = CGPoint(x: global.x - frame.minX, y: global.y - frame.minY)
        let surface = waterY(b.x)
        let box = CGRect(x: b.x - b.size, y: surface - b.size * 0.5, width: b.size * 2, height: b.size * 2.3)
        if box.contains(p) { b.sinking = 0; boat = b }
    }

    func drawBoat(_ c: CGContext) {
        guard let b = boat, water > 0 else { return }
        let s = b.size
        let brk = b.sinking >= 0 ? min(1, b.sinking * 1.0) : 0
        let sink = b.sinking >= 0 ? pow(b.sinking / 4, 1.4) * (s * 1.6 + 70) : 0
        let bob = sin(time * 1.3 + b.phase) * 2
        let cx = b.x, cy = waterY(b.x) - sink + bob
        let alpha = b.sinking >= 0 ? max(0, 1 - b.sinking / 4) : 1
        let hull = CGColor(red: 0.45, green: 0.28, blue: 0.16, alpha: 1)
        let hullDark = CGColor(red: 0.32, green: 0.2, blue: 0.11, alpha: 1)
        c.saveGState(); c.translateBy(x: cx, y: cy); c.setAlpha(alpha)

        func hullHalf(_ sign: CGFloat) {
            c.saveGState()
            c.rotate(by: sign * brk * 0.7)              // halves swing apart when broken
            c.translateBy(x: 0, y: -brk * s * 0.15)
            c.setFillColor(hull)
            c.move(to: CGPoint(x: 0, y: 0))
            c.addLine(to: CGPoint(x: sign * s, y: 0))
            c.addLine(to: CGPoint(x: sign * s * 0.7, y: -s * 0.42))
            c.addLine(to: CGPoint(x: 0, y: -s * 0.42))
            c.closePath(); c.fillPath()
            c.setFillColor(hullDark)
            c.fill(CGRect(x: min(0, sign * s), y: -3, width: s, height: 3))
            c.restoreGState()
        }
        hullHalf(1); hullHalf(-1)

        // mast + sails fall over as it breaks
        c.saveGState()
        c.rotate(by: brk * 1.1 * (b.vx >= 0 ? 1 : -1))
        c.setStrokeColor(hullDark); c.setLineWidth(2); c.setLineCap(.round)
        c.move(to: CGPoint(x: 0, y: 0)); c.addLine(to: CGPoint(x: 0, y: s * 1.7)); c.strokePath()
        let sails: [CGColor] = [
            CGColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1),
            CGColor(red: 0.86, green: 0.30, blue: 0.28, alpha: 1),
            CGColor(red: 0.30, green: 0.55, blue: 0.85, alpha: 1),
            CGColor(red: 0.95, green: 0.82, blue: 0.35, alpha: 1)]
        c.setFillColor(sails[b.hue % 4])
        c.move(to: CGPoint(x: s * 0.12, y: s * 1.62))
        c.addLine(to: CGPoint(x: s * 0.12, y: s * 0.12))
        c.addQuadCurve(to: CGPoint(x: s * 0.95, y: s * 0.22), control: CGPoint(x: s * 0.55, y: s * 0.1))
        c.closePath(); c.fillPath()
        c.setFillColor(sails[b.hue % 4].copy(alpha: 0.8)!)
        c.move(to: CGPoint(x: -s * 0.08, y: s * 1.45))
        c.addLine(to: CGPoint(x: -s * 0.08, y: s * 0.12))
        c.addLine(to: CGPoint(x: -s * 0.72, y: s * 0.18))
        c.closePath(); c.fillPath()
        c.restoreGState()

        c.restoreGState()
    }

    static let fishCols: [CGColor] = [
        CGColor(red: 0.98, green: 0.55, blue: 0.20, alpha: 0.9),   // clownfish orange
        CGColor(red: 0.80, green: 0.84, blue: 0.90, alpha: 0.85),  // silver
        CGColor(red: 0.30, green: 0.68, blue: 0.95, alpha: 0.85),  // blue
        CGColor(red: 0.96, green: 0.84, blue: 0.32, alpha: 0.9),   // yellow
    ]

    func drawCreatures(_ c: CGContext) {
        for f in fish {
            if f.kind == 0 { drawFish(c, f) } else { drawJelly(c, f) }
        }
    }

    func drawFish(_ c: CGContext, _ f: Fish) {
        let s = f.size
        c.saveGState()
        c.translateBy(x: f.x, y: f.y); c.scaleBy(x: f.dir, y: 1)
        // tail
        c.setFillColor(Simulation.fishCols[f.hue % 4].copy(alpha: 0.6)!)
        c.move(to: CGPoint(x: -s * 0.7, y: 0))
        c.addLine(to: CGPoint(x: -s * 1.25, y: s * 0.5))
        c.addLine(to: CGPoint(x: -s * 1.25, y: -s * 0.5))
        c.closePath(); c.fillPath()
        // body
        c.setFillColor(Simulation.fishCols[f.hue % 4])
        c.fillEllipse(in: CGRect(x: -s * 0.8, y: -s * 0.45, width: s * 1.7, height: s * 0.9))
        // top fin
        c.setFillColor(Simulation.fishCols[f.hue % 4].copy(alpha: 0.55)!)
        c.move(to: CGPoint(x: -s * 0.2, y: s * 0.35))
        c.addQuadCurve(to: CGPoint(x: s * 0.4, y: s * 0.3), control: CGPoint(x: s * 0.1, y: s * 0.85))
        c.fillPath()
        // eye
        c.setFillColor(CGColor(red: 0.08, green: 0.1, blue: 0.14, alpha: 0.95))
        c.fillEllipse(in: CGRect(x: s * 0.48, y: -s * 0.08, width: s * 0.2, height: s * 0.2))
        c.restoreGState()
    }

    func drawJelly(_ c: CGContext, _ f: Fish) {
        let s = f.size
        let pulse = 1 + 0.12 * sin(time * 3 + f.phase)
        c.saveGState()
        c.translateBy(x: f.x, y: f.y)
        c.setFillColor(CGColor(red: 0.74, green: 0.55, blue: 0.95, alpha: 0.42))
        // bell (upper half-ellipse)
        c.move(to: CGPoint(x: -s * pulse, y: 0))
        c.addCurve(to: CGPoint(x: s * pulse, y: 0),
                   control1: CGPoint(x: -s * pulse, y: s * 1.3),
                   control2: CGPoint(x: s * pulse, y: s * 1.3))
        c.closePath(); c.fillPath()
        // tentacles
        c.setStrokeColor(CGColor(red: 0.8, green: 0.6, blue: 1, alpha: 0.35)); c.setLineWidth(1.2); c.setLineCap(.round)
        for k in 0..<5 {
            let tx = (-s * 0.7) + CGFloat(k) * s * 0.35
            c.move(to: CGPoint(x: tx, y: 0))
            for seg in 1...4 {
                let yy = -CGFloat(seg) * s * 0.4
                let xx = tx + sin(time * 4 + f.phase + CGFloat(seg) * 0.9 + CGFloat(k)) * s * 0.18
                c.addLine(to: CGPoint(x: xx, y: yy))
            }
        }
        c.strokePath()
        c.restoreGState()
    }

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
        if p.kind == .runoff {                            // trickle reaches the water: absorbed
            if ripples.count < 90 { ripples.append((x: p.x, t: time)) }
            water = min(bounds.maxY - 6, water + 0.02)
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
        // fish and sea creatures (clipped to the water body)
        drawCreatures(c)

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
