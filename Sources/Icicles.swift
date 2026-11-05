// Macscapes — icicles that slowly grow down from the bottom edge of windows, widgets, etc. while it
// is snowing, melt back in warmer weather, and break off and fall when the cursor drags across them
// or the window is moved.

import Cocoa

struct Icicle {
    var dx: CGFloat         // x offset from the pile's left edge
    var len: CGFloat = 0
    var maxLen: CGFloat
    var w: CGFloat
    var rate: CGFloat       // growth speed (px/sec)
    var phase: CGFloat
}

/// An icicle that has broken loose and is falling.
struct IceShard {
    var x: CGFloat, y: CGFloat      // centre
    var vx: CGFloat, vy: CGFloat
    var len: CGFloat, w: CGFloat
    var rot: CGFloat, vrot: CGFloat
}

extension Simulation {
    private func seedIcicles(_ pile: Pile) {
        let w = pile.rect.width
        var x = rnd(6, 22)
        while x < w - 6 {
            pile.icicles.append(Icicle(dx: x, maxLen: rnd(6, 30), w: rnd(2.4, 4.2),
                                       rate: rnd(0.4, 1.1), phase: rnd(0, .pi * 2)))
            x += rnd(11, 32)
        }
    }

    /// Knock every icicle off a pile (used when the window moves).
    func breakIcicles(_ pile: Pile, vx: CGFloat = 0, vy: CGFloat = 0) {
        guard !pile.icicles.isEmpty else { return }
        let fx = clamp(vx, -1400, 1400), fy = clamp(vy, -1400, 1400)
        for ic in pile.icicles where ic.len > 1.2 {
            iceFalls.append(IceShard(x: pile.rect.minX + ic.dx, y: pile.rect.minY - ic.len / 2,
                                     vx: fx * 0.3 + rnd(-30, 30), vy: min(0, fy * 0.25) - rnd(0, 40),
                                     len: ic.len, w: ic.w, rot: 0, vrot: rnd(-5, 5)))
        }
        pile.icicles.removeAll()
    }

    func stepIcicles(_ dt: CGFloat) {
        let cold = effect == .snow
        let speed = CGFloat(Settings.intensity)
        let mSpeed = hypot(mouseVel.dx, mouseVel.dy)
        for pile in order where !pile.isGround {
            if pile.rect.width < 60 || pile.rect.height < 40 {
                if !pile.icicles.isEmpty { pile.icicles.removeAll() }
                continue
            }
            if cold {
                if pile.icicles.isEmpty { seedIcicles(pile) }
                for i in pile.icicles.indices {
                    pile.icicles[i].len = min(pile.icicles[i].maxLen,
                                              pile.icicles[i].len + pile.icicles[i].rate * speed * dt)
                }
            } else if !pile.icicles.isEmpty {
                for i in pile.icicles.indices { pile.icicles[i].len = max(0, pile.icicles[i].len - 5 * dt) }
                pile.icicles.removeAll { $0.len <= 0.2 }
            }
            // drag the cursor across them → they snap off
            if !pile.icicles.isEmpty && mSpeed > 12 {
                let topY = pile.rect.minY
                pile.icicles.removeAll { ic in
                    guard ic.len > 3 else { return false }
                    let x = pile.rect.minX + ic.dx
                    guard mouse.x > x - ic.w - 3, mouse.x < x + ic.w + 3,
                          mouse.y < topY + 4, mouse.y > topY - ic.len - 4 else { return false }
                    iceFalls.append(IceShard(x: x, y: topY - ic.len / 2,
                                             vx: mouseVel.dx * 0.18 + rnd(-20, 20),
                                             vy: -rnd(10, 50), len: ic.len, w: ic.w, rot: 0, vrot: rnd(-6, 6)))
                    return true
                }
            }
        }
        stepIceFalls(dt)
    }

    private func stepIceFalls(_ dt: CGFloat) {
        guard !iceFalls.isEmpty else { return }
        var kept: [IceShard] = []
        for var s in iceFalls {
            s.vy -= 1500 * dt
            s.vx *= 1 - 0.25 * dt
            s.x += s.vx * dt; s.y += s.vy * dt
            s.rot += s.vrot * dt
            let surface = water > 0 ? waterY(s.x) : groundY
            if s.y - s.len / 2 <= surface {               // tip reached the ground / water
                shatterIce(CGPoint(x: s.x, y: surface + 2), len: s.len)
                if water > 0, ripples.count < 90 { ripples.append((x: s.x, t: time)) }
                continue
            }
            if s.y < -80 || s.x < -80 || s.x > bounds.maxX + 80 { continue }
            kept.append(s)
        }
        iceFalls = kept
    }

    private func shatterIce(_ p: CGPoint, len: CGFloat) {
        let n = min(16, Int(len / 3) + 3)
        for _ in 0..<n {
            let a = rnd(0.2, .pi - 0.2), s = rnd(40, 170)
            particles.append(P(x: p.x, y: p.y, vx: cos(a) * s, vy: sin(a) * s * 0.7,
                               size: rnd(1.2, 2.6), maxLife: effect == .snow ? .infinity : 0.6))
        }
    }

    // MARK: drawing

    private func icicleBody(_ path: CGMutablePath, _ cx: CGFloat, _ topY: CGFloat, _ len: CGFloat,
                            _ w: CGFloat, _ wob: CGFloat) {
        let ht = w * 0.5
        path.move(to: CGPoint(x: cx - ht, y: topY))
        path.addQuadCurve(to: CGPoint(x: cx + wob, y: topY - len),
                          control: CGPoint(x: cx - ht * 0.7 + wob * 0.4, y: topY - len * 0.55))
        path.addQuadCurve(to: CGPoint(x: cx + ht, y: topY),
                          control: CGPoint(x: cx + ht * 0.7 + wob * 0.4, y: topY - len * 0.55))
        path.closeSubpath()
    }

    func drawIcicles(_ c: CGContext) {
        let bodies = CGMutablePath(), highlights = CGMutablePath(), tops = CGMutablePath(), tips = CGMutablePath()
        var any = false
        for pile in order where !pile.isGround && !pile.icicles.isEmpty {
            let r = pile.rect
            for ic in pile.icicles where ic.len > 0.6 {
                any = true
                let x = r.minX + min(max(ic.dx, 2), r.width - 2)
                let topY = r.minY
                let w = ic.w * clamp(ic.len / 6, 0.45, 1)     // thin when young, fattening as it grows
                let wob = sin(ic.phase) * min(2.5, ic.len * 0.05)
                icicleBody(bodies, x, topY, ic.len, w, wob)
                if ic.len > 3 {
                    // glassy streak down the front
                    highlights.move(to: CGPoint(x: x - w * 0.16, y: topY - 1))
                    highlights.addQuadCurve(to: CGPoint(x: x - w * 0.04 + wob, y: topY - ic.len * 0.82),
                                            control: CGPoint(x: x - w * 0.2, y: topY - ic.len * 0.42))
                    highlights.addQuadCurve(to: CGPoint(x: x + w * 0.04, y: topY - 1),
                                            control: CGPoint(x: x - w * 0.02, y: topY - ic.len * 0.42))
                    highlights.closeSubpath()
                    tips.addEllipse(in: CGRect(x: x + wob - 0.9, y: topY - ic.len - 0.9, width: 1.8, height: 1.8))
                }
                tops.addEllipse(in: CGRect(x: x - w * 0.75, y: topY - 1.4, width: w * 1.5, height: 3.2))
            }
        }
        if any { drawIceShapes(c, bodies, highlights, tops, tips) }

        // falling shards
        for s in iceFalls {
            c.saveGState()
            c.translateBy(x: s.x, y: s.y); c.rotate(by: s.rot)
            let body = CGMutablePath(), hi = CGMutablePath(), tp = CGMutablePath(), ti = CGMutablePath()
            icicleBody(body, 0, s.len / 2, s.len, s.w, 0)
            hi.move(to: CGPoint(x: -s.w * 0.16, y: s.len / 2 - 1))
            hi.addLine(to: CGPoint(x: -s.w * 0.04, y: -s.len / 2 + 2))
            drawIceShapes(c, body, hi, tp, ti)
            c.restoreGState()
        }
    }

    private func drawIceShapes(_ c: CGContext, _ bodies: CGPath, _ highlights: CGPath,
                               _ tops: CGPath, _ tips: CGPath) {
        c.saveGState()
        c.addPath(bodies)
        c.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 2.5,
                    color: CGColor(red: 0.45, green: 0.6, blue: 0.82, alpha: 0.35))
        c.setFillColor(CGColor(red: 0.74, green: 0.86, blue: 0.97, alpha: 0.5))
        c.fillPath()
        c.restoreGState()
        // crisp icy rim
        c.addPath(bodies)
        c.setStrokeColor(CGColor(red: 0.88, green: 0.95, blue: 1, alpha: 0.6))
        c.setLineWidth(0.7); c.setLineJoin(.round); c.strokePath()
        // frosted base, glassy streak, tip glints
        c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
        c.addPath(tops); c.fillPath()
        c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.4))
        c.addPath(highlights); c.fillPath()
        c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        c.addPath(tips); c.fillPath()
    }
}
