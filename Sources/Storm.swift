// Drift — thunderstorm lightning, tornado funnel, and flying storm debris.

import Cocoa

struct Bolt {
    var main: [CGPoint]
    var branches: [[CGPoint]]
    var life: CGFloat = 0
}

final class Tornado {
    var x: CGFloat
    let dir: CGFloat
    let speed: CGFloat
    var groundY: CGFloat
    let topY: CGFloat
    var life: CGFloat = 0
    var strength: CGFloat = 0

    init(x: CGFloat, dir: CGFloat, speed: CGFloat, groundY: CGFloat, topY: CGFloat) {
        self.x = x; self.dir = dir; self.speed = speed; self.groundY = groundY; self.topY = topY
    }

    @inline(__always) func frac(_ y: CGFloat) -> CGFloat { clamp((y - groundY) / (topY - groundY), 0, 1) }

    /// The funnel's centre line: snakes, and leans back from the direction it travels.
    func axisX(_ y: CGFloat, _ t: CGFloat) -> CGFloat {
        let f = frac(y)
        return x + sin(t * 1.1 + y * 0.008) * 28 * f + sin(t * 0.47) * 18 * f * f - dir * f * 70
    }

    func radius(_ y: CGFloat) -> CGFloat {
        let f = frac(y)
        return 14 + f * 34 + f * f * f * 170
    }

    /// Sucks particles in, swirls them, and lifts them up the funnel.
    func pull(_ p: inout P, dt: CGFloat, time t: CGFloat) {
        guard strength > 0.01, p.y > groundY - 20, p.y < topY + 60 else { return }
        let ax = axisX(p.y, t), R = radius(p.y) * 2.4 + 40
        let dx = p.x - ax
        guard abs(dx) < R else { return }
        let f = (1 - abs(dx) / R) * strength
        let r = radius(p.y)
        p.vx += (-dx * 3.2 + cos(t * 7 + p.phase * 3) * r * 7 + dir * speed * 1.5) * f * dt
        p.vy += (p.hue >= 20 ? 1500 : 1100) * f * dt
        if p.vy > 720 { p.vy = 720 }
        p.rot += 14 * f * dt
    }

    func draw(_ c: CGContext, time t: CGFloat) {
        guard strength > 0.01 else { return }
        let steps = 56
        let h = topY - groundY
        c.saveGState()
        c.setAlpha(strength)

        // cloud it hangs from
        let cloud = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [CGColor(red: 0.20, green: 0.22, blue: 0.26, alpha: 0.55),
                                        CGColor(red: 0.20, green: 0.22, blue: 0.26, alpha: 0)] as CFArray,
                               locations: [0, 1])!
        let top = CGPoint(x: axisX(topY, t), y: topY - 10)
        c.drawRadialGradient(cloud, startCenter: top, startRadius: 0, endCenter: top, endRadius: 360, options: [])

        // funnel body
        let body = CGMutablePath()
        for i in 0...steps {
            let y = groundY + h * CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: axisX(y, t) - radius(y), y: y)
            if i == 0 { body.move(to: p) } else { body.addLine(to: p) }
        }
        for i in stride(from: steps, through: 0, by: -1) {
            let y = groundY + h * CGFloat(i) / CGFloat(steps)
            body.addLine(to: CGPoint(x: axisX(y, t) + radius(y), y: y))
        }
        body.closeSubpath()
        c.saveGState()
        c.addPath(body); c.clip()
        let fill = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [CGColor(red: 0.42, green: 0.36, blue: 0.29, alpha: 0.75),
                                       CGColor(red: 0.36, green: 0.37, blue: 0.40, alpha: 0.55),
                                       CGColor(red: 0.30, green: 0.32, blue: 0.36, alpha: 0.35)] as CFArray,
                              locations: [0, 0.35, 1])!
        c.drawLinearGradient(fill, start: CGPoint(x: 0, y: groundY), end: CGPoint(x: 0, y: topY), options: [])
        // spinning bands (front half brighter, back half darker)
        c.setLineWidth(1.4)
        for k in 0..<16 {
            let path = CGMutablePath(), back = CGMutablePath()
            var lastFront: Bool? = nil
            for i in 0...steps {
                let y = groundY + h * CGFloat(i) / CGFloat(steps)
                let ph = t * 6.5 + CGFloat(k) * 0.39 + y * 0.03
                let pt = CGPoint(x: axisX(y, t) + sin(ph) * radius(y) * 0.96, y: y)
                let front = cos(ph) > 0
                let target = front ? path : back
                if lastFront != front { target.move(to: pt) } else { target.addLine(to: pt) }
                lastFront = front
            }
            c.setStrokeColor(CGColor(red: 0.78, green: 0.76, blue: 0.72, alpha: 0.28))
            c.addPath(path); c.strokePath()
            c.setStrokeColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.25))
            c.addPath(back); c.strokePath()
        }
        c.restoreGState()

        // debris cloud at the base
        let dust = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [CGColor(red: 0.50, green: 0.40, blue: 0.28, alpha: 0.6),
                                       CGColor(red: 0.50, green: 0.40, blue: 0.28, alpha: 0)] as CFArray,
                              locations: [0, 1])!
        let base = CGPoint(x: axisX(groundY, t), y: groundY + 14)
        c.saveGState()
        c.translateBy(x: base.x, y: base.y); c.scaleBy(x: 1.6, y: 0.7)
        c.drawRadialGradient(dust, startCenter: .zero, startRadius: 0, endCenter: .zero,
                             endRadius: 70 + 14 * sin(t * 3), options: [])
        c.restoreGState()
        c.restoreGState()
    }
}

extension Simulation {
    func randomDebrisHue() -> Int { [20, 21, 22, 23, 24, 20, 22, 30, 30, 31].randomElement()! }

    // MARK: lightning

    func strikeBolt() {
        let x0 = rnd(0.1, 0.9) * bounds.width
        let tx = clamp(x0 + rnd(-220, 220), 20, bounds.maxX - 20)
        // strike the highest surface under the target (window, widget, icon, or the Dock/ground)
        var ty = groundY
        for pile in order where !pile.isGround && tx >= pile.rect.minX && tx <= pile.rect.maxX {
            let top = pile.base(tx) + pile.height(at: tx)
            if top > ty && top < bounds.maxY - 40 { ty = top }
        }
        if water > 0 { ty = max(ty, waterY(tx)) }      // flooded: the bolt hits the water
        var pts = [CGPoint(x: x0, y: bounds.maxY + 10)]
        var cur = pts[0]
        while cur.y > ty + 1 {
            let remaining = cur.y - ty
            let step = min(remaining, rnd(14, 38))
            let pull = (tx - cur.x) * step / remaining
            cur = CGPoint(x: cur.x + pull + rnd(-20, 20), y: cur.y - step)
            pts.append(cur)
        }
        pts[pts.count - 1] = CGPoint(x: tx, y: ty)
        var branches: [[CGPoint]] = []
        if pts.count > 4 {
            for _ in 0..<Int.random(in: 2...5) {
                let i = Int.random(in: 1..<(pts.count - 2))
                var q = pts[i], b = [q]
                let side: CGFloat = Bool.random() ? 1 : -1
                for _ in 0..<Int.random(in: 3...8) {
                    q = CGPoint(x: q.x + side * rnd(6, 26), y: q.y - rnd(10, 28))
                    b.append(q)
                }
                branches.append(b)
            }
        }
        bolts.append(Bolt(main: pts, branches: branches))
        // impact
        for _ in 0..<30 {
            let a = rnd(0.1, .pi - 0.1), s = rnd(80, 320)
            particles.append(P(x: tx, y: ty + 1, vx: cos(a) * s, vy: sin(a) * s, size: rnd(0.9, 2),
                               maxLife: rnd(0.3, 0.8), hue: Int.random(in: 0...2), kind: .spark))
        }
    }

    func drawBolts(_ c: CGContext) {
        for b in bolts {
            let t = b.life
            let vis: CGFloat = t < 0.07 ? 1 : t < 0.12 ? 0.2 : max(0, 1 - (t - 0.12) / 0.33)
            guard vis > 0.01 else { continue }
            c.saveGState()
            c.setLineCap(.round); c.setLineJoin(.round)
            c.setShadow(offset: .zero, blur: 18, color: CGColor(red: 0.65, green: 0.78, blue: 1, alpha: 0.95 * vis))
            let main = CGMutablePath(); main.addLines(between: b.main)
            let br = CGMutablePath(); for line in b.branches { br.addLines(between: line) }
            c.setStrokeColor(CGColor(red: 0.8, green: 0.88, blue: 1, alpha: 0.55 * vis))
            c.setLineWidth(1.4); c.addPath(br); c.strokePath()
            c.setStrokeColor(CGColor(red: 0.82, green: 0.9, blue: 1, alpha: 0.9 * vis))
            c.setLineWidth(3.6); c.addPath(main); c.strokePath()
            c.setShadow(offset: .zero, blur: 0, color: nil)
            c.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: vis))
            c.setLineWidth(1.4); c.addPath(main); c.strokePath()
            c.restoreGState()
        }
    }

    // MARK: tornado

    func stepTornado(_ dt: CGFloat) {
        guard let tw = tornado else {
            nextTornado -= dt
            if nextTornado <= 0 {
                let dir: CGFloat = Settings.windAngle > 2 ? 1 : Settings.windAngle < -2 ? -1 : (Bool.random() ? 1 : -1)
                tornado = Tornado(x: dir > 0 ? -220 : bounds.maxX + 220, dir: dir, speed: rnd(70, 140),
                                  groundY: groundY, topY: bounds.maxY + 40)
            }
            return
        }
        tw.life += dt
        tw.x += tw.dir * tw.speed * dt
        tw.groundY = max(groundY, water)              // over a flood, it touches down on the water
        let edge = tw.dir > 0 ? bounds.maxX + 260 - tw.x : tw.x + 260
        tw.strength = min(1, tw.life / 2.5) * clamp(edge / 260, 0, 1)
        if edge <= 0 { tornado = nil; nextTornado = rnd(18, 40); return }

        // rip resting debris off the surfaces it passes
        for pile in order where !pile.rest.isEmpty {
            let r = pile.rect
            pile.rest.removeAll { s in
                let x = r.minX + s.dx, y = r.maxY + s.dy
                guard abs(x - tw.axisX(y, time)) < tw.radius(y) * 1.8 + 30 else { return false }
                var q = P(x: x, y: y + 3, vx: rnd(-80, 80), vy: rnd(200, 420), size: s.size, hue: s.hue)
                q.rot = s.rot; q.vrot = rnd(-10, 10); q.ignoreID = pile.id; q.ignoreT = 0.3
                particles.append(q)
                return true
            }
        }
        // kick debris up from the ground
        if CGFloat.random(in: 0...1) < dt * 14 * tw.strength {
            let bx = tw.axisX(groundY, time)
            var q = P(x: bx + rnd(-40, 40), y: groundY + 6, vx: rnd(-120, 120), vy: rnd(250, 480),
                      size: rnd(5, 9), hue: randomDebrisHue())
            q.rot = rnd(0, .pi * 2); q.vrot = rnd(-12, 12)
            particles.append(q)
        }
    }

    // MARK: debris drawing

    func drawStormDebris(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ rot: CGFloat,
                         _ flip: CGFloat, _ hue: Int, _ a: CGFloat) {
        if hue >= 20 && hue <= 24 { drawLeaf(c, x, y, s, rot, flip, hue - 20, a); return }
        c.saveGState()
        c.translateBy(x: x, y: y); c.rotate(by: rot); c.scaleBy(x: 1, y: flip == 0 ? 1 : flip)
        c.setAlpha(a)
        if hue == 30 {      // twig
            c.setStrokeColor(CGColor(red: 0.40, green: 0.26, blue: 0.14, alpha: 1))
            c.setLineWidth(1.5); c.setLineCap(.round)
            c.move(to: CGPoint(x: -s * 0.9, y: 0)); c.addLine(to: CGPoint(x: s * 0.9, y: s * 0.1))
            c.move(to: CGPoint(x: s * 0.2, y: s * 0.05)); c.addLine(to: CGPoint(x: s * 0.55, y: s * 0.45))
            c.strokePath()
        } else {            // scrap of paper
            let r = CGRect(x: -s * 0.65, y: -s * 0.45, width: s * 1.3, height: s * 0.9)
            c.setFillColor(CGColor(red: 0.93, green: 0.91, blue: 0.85, alpha: 1))
            c.fill(r)
            c.setStrokeColor(CGColor(red: 0.55, green: 0.6, blue: 0.75, alpha: 0.6)); c.setLineWidth(0.6)
            for k in 0..<3 {
                let ly = r.minY + r.height * (0.28 + 0.24 * CGFloat(k))
                c.move(to: CGPoint(x: r.minX + 2, y: ly)); c.addLine(to: CGPoint(x: r.maxX - 2, y: ly))
            }
            c.strokePath()
        }
        c.restoreGState()
    }
}
