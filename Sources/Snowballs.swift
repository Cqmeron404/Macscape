// Drift — snowballs and snowmen.
//
// Hold ⌥ Option with the pointer over fallen snow to pack a snowball (it grows as you
// move along the pile). Move and release Option to throw it. Slow landings settle; fast
// impacts burst into snow that piles up. Three balls stacked become a snowman, which can
// be picked up with Option and thrown too.

import Cocoa

extension Simulation {
    static let burstBall: CGFloat = 400      // impact speed (pt/s) that bursts a ball
    static let burstMan: CGFloat = 330       // … or a snowman

    func pile(_ id: Int?) -> Pile? {
        guard let id else { return nil }
        return id == ground.id ? ground : piles[id]
    }

    // MARK: per-frame

    func stepBodies(_ dt: CGFloat) {
        let flags = NSEvent.modifierFlags.intersection([.option, .command, .control, .shift])
        let opt = flags == .option
        let here = bounds.contains(mouse)

        if opt && !optionDown && here { optionDown = true; beginGrab() }
        else if !opt && optionDown { optionDown = false; release() }

        if let b = heldBall {
            b.x = mouse.x; b.y = mouse.y
            b.spin += mouseVel.dx * dt * 0.02
            if b.r < 34 {
                let got = takeSnow(at: mouse, amount: 46 * dt)
                if got > 0 { b.r = min(34, b.r + got * 0.32) }
            }
        }
        if let m = heldMan {
            m.x = mouse.x - m.grabDX; m.y = mouse.y - m.grabDY
            m.tilt += (clamp(-mouseVel.dx * 0.0004, -0.35, 0.35) - m.tilt) * min(1, 8 * dt)
        }

        for b in balls where !b.held && !b.dead { stepBall(b, dt) }
        for m in men where !m.held && !m.dead { stepMan(m, dt) }
        collideBalls()
        buildSnowmen()
        balls.removeAll { $0.dead }
        men.removeAll { $0.dead }
    }

    // MARK: grabbing

    func beginGrab() {
        for m in men where !m.dead {
            for (i, c) in m.centres.enumerated() where hypot(c.x - mouse.x, c.y - mouse.y) < m.r[i] + 6 {
                m.held = true; m.resting = false; m.restPile = nil
                m.grabDX = mouse.x - m.x; m.grabDY = mouse.y - m.y
                heldMan = m
                return
            }
        }
        for b in balls where !b.dead && hypot(b.x - mouse.x, b.y - mouse.y) < b.r + 6 {
            b.held = true; b.resting = false; b.restPile = nil; b.restBall = nil
            heldBall = b
            return
        }
        guard balls.count < 40, takeSnow(at: mouse, amount: 1.2) > 0.05 else { return }
        let b = Ball(x: mouse.x, y: mouse.y, r: 5)
        b.held = true
        balls.append(b)
        heldBall = b
    }

    func release() {
        let vx = clamp(mouseVel.dx * 1.1, -2800, 2800), vy = clamp(mouseVel.dy * 1.1, -2800, 2800)
        if let b = heldBall {
            b.held = false
            if b.r < 6.5 { burst(x: b.x, y: b.y, r: b.r, vx: 0, vy: 0, onto: nil); b.dead = true }
            else { b.vx = vx; b.vy = vy }
            heldBall = nil
        }
        if let m = heldMan {
            m.held = false; m.vx = vx; m.vy = vy
            heldMan = nil
        }
    }

    /// Scoops snow from the pile under/near `p`. Returns how much was taken.
    func takeSnow(at p: CGPoint, amount: CGFloat) -> CGFloat {
        for pile in order {
            let r = pile.rect
            guard p.x >= r.minX - 6, p.x <= r.maxX + 6 else { continue }
            let x = clamp(p.x, r.minX, r.maxX - 0.01)
            let i = pile.index(x)
            let base = pile.base(x), top = base + pile.h[i]
            guard p.y > base - 16, p.y < top + 48 else { continue }
            var taken: CGFloat = 0
            for j in max(0, i - 4)...min(pile.h.count - 1, i + 4) {
                let t = min(pile.h[j], amount / 9)
                pile.h[j] -= t; taken += t
            }
            return taken
        }
        return 0
    }

    // MARK: windows moving under bodies

    func carryBodies(_ id: Int, dx: CGFloat, dy: CGFloat, vx: CGFloat, vy: CGFloat, release: Bool = false) {
        let fast = release || hypot(vx, vy) > 260
        let fvx = clamp(vx, -2500, 2500) * 0.9, fvy = clamp(vy, -2500, 2500) * 0.9
        for b in balls where b.resting && b.restPile == id {
            b.x += dx; b.y += dy
            if fast { b.resting = false; b.restPile = nil; b.vx = fvx; b.vy = fvy + 40 }
        }
        for m in men where m.resting && m.restPile == id {
            m.x += dx; m.y += dy
            if fast { m.resting = false; m.restPile = nil; m.vx = fvx; m.vy = fvy + 40 }
        }
        // balls stacked on carried balls follow through their restBall link
    }

    // MARK: physics

    enum BodyHit { case none, rest(Pile), burst(Pile?) }

    /// Circle vs every surface (windows, widgets, icons, ground) and the screen sides.
    func collide(cx: inout CGFloat, cy: inout CGFloat, vx: inout CGFloat, vy: inout CGFloat,
                 r: CGFloat, px: CGFloat, py: CGFloat, burstAt: CGFloat) -> BodyHit {
        for pile in order {
            let R = pile.rect
            if cx + r <= R.minX || cx - r >= R.maxX { continue }
            // released behind a window: let it fall out from behind without colliding
            if !pile.isGround && R.contains(CGPoint(x: px, y: py)) { continue }
            let xc = clamp(cx, R.minX, R.maxX - 0.01)
            let base = pile.base(xc), surf = base + pile.height(at: xc)

            // landing on top
            if cx >= R.minX - r * 0.3, cx <= R.maxX + r * 0.3, cy - r < surf, py >= base {
                let speed = -vy
                if speed > burstAt { return .burst(pile) }
                cy = surf + r * 0.85
                if speed > 110 { vy = speed * 0.22; vx *= 0.75; return .none }
                vy = 0
                return .rest(pile)
            }
            if pile.isGround { continue }
            // sides and underside
            guard cy + r > R.minY, cy - r < base else { continue }
            if px + r <= R.minX + 2 {
                if vx > burstAt { return .burst(nil) }
                cx = R.minX - r; vx = -vx * 0.3
            } else if px - r >= R.maxX - 2 {
                if -vx > burstAt { return .burst(nil) }
                cx = R.maxX + r; vx = -vx * 0.3
            } else if py + r <= R.minY + 2 {
                if vy > burstAt { return .burst(nil) }
                cy = R.minY - r; vy = -vy * 0.3
            }
        }
        // screen edges act as walls
        if cx - r < 0 {
            if px - r >= -1 && -vx > burstAt { return .burst(nil) }
            cx = r; vx = abs(vx) * 0.35
        } else if cx + r > bounds.maxX {
            if px + r <= bounds.maxX + 1 && vx > burstAt { return .burst(nil) }
            cx = bounds.maxX - r; vx = -abs(vx) * 0.35
        }
        return .none
    }

    func stepBall(_ b: Ball, _ dt: CGFloat) {
        if b.resting {
            if let s = b.restBall {
                if s.dead || s.held || !s.resting {
                    b.resting = false; b.restBall = nil
                } else {
                    b.x += (s.x - b.x) * min(1, 10 * dt)
                    b.y = s.y + (s.r + b.r) * 0.82
                    return
                }
            } else if let p = pile(b.restPile), b.x >= p.rect.minX, b.x <= p.rect.maxX {
                b.vx *= max(0, 1 - 6 * dt)
                b.x += b.vx * dt
                b.spin += b.vx * dt / max(4, b.r)
                b.y = p.base(b.x) + p.height(at: b.x) + b.r * 0.85
                return
            } else {
                b.resting = false; b.restPile = nil   // rolled off the edge / surface vanished
            }
        }
        let px = b.x, py = b.y
        b.vy -= 1100 * dt
        b.x += b.vx * dt; b.y += b.vy * dt
        b.spin += b.vx * dt / max(4, b.r)
        switch collide(cx: &b.x, cy: &b.y, vx: &b.vx, vy: &b.vy, r: b.r, px: px, py: py, burstAt: Simulation.burstBall) {
        case .none: break
        case .rest(let p): b.resting = true; b.restPile = p.id
        case .burst(let p):
            burst(x: b.x, y: b.y, r: b.r, vx: b.vx, vy: b.vy, onto: p); b.dead = true
        }
        if b.y < -300 { b.dead = true }

        // a flying ball hitting a snowman
        for m in men where !m.dead && !m.held {
            for (i, c) in m.centres.enumerated() where hypot(c.x - b.x, c.y - b.y) < m.r[i] + b.r {
                if hypot(b.vx - m.vx, b.vy - m.vy) > Simulation.burstBall {
                    burstSnowman(m); burst(x: b.x, y: b.y, r: b.r, vx: b.vx * 0.3, vy: b.vy * 0.3, onto: nil); b.dead = true
                } else {
                    let d = max(0.01, hypot(b.x - c.x, b.y - c.y))
                    let nx = (b.x - c.x) / d, ny = (b.y - c.y) / d
                    b.x = c.x + nx * (m.r[i] + b.r); b.y = c.y + ny * (m.r[i] + b.r)
                    let vn = b.vx * nx + b.vy * ny
                    if vn < 0 { b.vx -= 1.3 * vn * nx; b.vy -= 1.3 * vn * ny }
                }
                break
            }
        }
    }

    func stepMan(_ m: Snowman, _ dt: CGFloat) {
        if m.resting {
            if let p = pile(m.restPile), m.x >= p.rect.minX, m.x <= p.rect.maxX {
                m.vx *= max(0, 1 - 6 * dt)
                m.x += m.vx * dt
                m.y = p.base(m.x) + p.height(at: m.x) + m.r[0] * 0.85 - m.r[0] * 0.88
                m.tilt *= max(0, 1 - 8 * dt)
                return
            }
            m.resting = false; m.restPile = nil
        }
        let off = m.r[0] * 0.88
        var cx = m.x, cy = m.y + off
        let px = cx, py = cy
        m.vy -= 1100 * dt
        cx += m.vx * dt; cy += m.vy * dt
        m.tilt += (clamp(-m.vx * 0.0004, -0.45, 0.45) - m.tilt) * min(1, 4 * dt)
        let hit = collide(cx: &cx, cy: &cy, vx: &m.vx, vy: &m.vy, r: m.r[0], px: px, py: py, burstAt: Simulation.burstMan)
        m.x = cx; m.y = cy - off
        switch hit {
        case .none: break
        case .rest(let p): m.resting = true; m.restPile = p.id
        case .burst(let p): burstSnowman(m, onto: p); return
        }
        // head and middle can smash into things too (thrown sideways or upward)
        let cs = m.centres
        for i in 1...2 {
            var hx = cs[i].x, hy = cs[i].y, hvx = m.vx, hvy = m.vy
            let hpx = hx - m.vx * dt, hpy = hy - m.vy * dt
            if case .burst = collide(cx: &hx, cy: &hy, vx: &hvx, vy: &hvy, r: m.r[i], px: hpx, py: hpy,
                                     burstAt: Simulation.burstMan) {
                burstSnowman(m); return
            }
        }
        if m.y < -400 { m.dead = true }
    }

    func collideBalls() {
        let bs = balls.filter { !$0.dead && !$0.held }
        guard bs.count > 1 else { return }
        for i in 0..<(bs.count - 1) {
            for j in (i + 1)..<bs.count {
                let a = bs[i], b = bs[j]
                if a.dead || b.dead || a.restBall === b || b.restBall === a { continue }
                let dx = a.x - b.x, dy = a.y - b.y
                let d = hypot(dx, dy), minD = (a.r + b.r) * 0.92
                guard d < minD, d > 0.01 else { continue }
                if hypot(a.vx - b.vx, a.vy - b.vy) > Simulation.burstBall + 80 {
                    burst(x: a.x, y: a.y, r: a.r, vx: a.vx * 0.3, vy: a.vy * 0.3, onto: nil); a.dead = true
                    burst(x: b.x, y: b.y, r: b.r, vx: b.vx * 0.3, vy: b.vy * 0.3, onto: nil); b.dead = true
                    continue
                }
                let (top, bot) = a.y >= b.y ? (a, b) : (b, a)
                let ny = abs(dy) / d
                if ny > 0.55 && bot.resting && !top.resting && hypot(top.vx, top.vy) < 420 {
                    top.resting = true; top.restBall = bot; top.restPile = nil
                    top.vx = 0; top.vy = 0
                    continue
                }
                // push apart
                let nx = dx / d, nyy = dy / d, push = minD - d
                func shove(_ m: Ball, _ s: CGFloat) {
                    m.x += nx * push * s; m.y += nyy * push * s
                    let vn = (m.vx * nx + m.vy * nyy) * (s > 0 ? 1 : -1)
                    if vn < 0 { m.vx -= 1.3 * vn * nx * (s > 0 ? 1 : -1); m.vy -= 1.3 * vn * nyy * (s > 0 ? 1 : -1) }
                }
                switch (a.resting, b.resting) {
                case (true, false): shove(b, -1)
                case (false, true): shove(a, 1)
                case (false, false): shove(a, 0.5); shove(b, -0.5)
                case (true, true):
                    if a.restBall == nil && b.restBall == nil {   // side by side on a surface
                        a.x += nx * push * 0.5; b.x -= nx * push * 0.5
                    }
                }
            }
        }
    }

    func buildSnowmen() {
        guard men.count < 14 else { return }
        for c in balls where !c.dead && c.resting && c.restBall == nil && c.restPile != nil {
            guard let b = balls.first(where: { !$0.dead && $0.resting && $0.restBall === c }),
                  let a = balls.first(where: { !$0.dead && $0.resting && $0.restBall === b }),
                  abs(b.x - c.x) < c.r * 0.3, abs(a.x - b.x) < b.r * 0.3
            else { continue }
            let radii = [c.r, b.r, a.r].sorted(by: >)
            let surf = c.y - c.r * 0.85
            let m = Snowman(x: c.x, y: surf, r: radii)
            m.resting = true; m.restPile = c.restPile
            a.dead = true; b.dead = true; c.dead = true
            men.append(m)
            // a little sparkle of snow as it comes together
            for p in m.centres {
                for _ in 0..<8 {
                    let ang = rnd(0, .pi * 2)
                    particles.append(P(x: p.x + cos(ang) * radii[0] * 0.8, y: p.y + sin(ang) * radii[0] * 0.8,
                                       vx: cos(ang) * rnd(20, 70), vy: rnd(30, 110), size: rnd(1, 2.2)))
                }
            }
        }
    }

    // MARK: bursting

    func burst(x: CGFloat, y: CGFloat, r: CGFloat, vx: CGFloat, vy: CGFloat, onto pile: Pile?) {
        let n = min(340, Int(r * r * 0.45) + 10)
        for _ in 0..<n {
            let a = rnd(0, .pi * 2), d = sqrt(rnd(0, 1)) * r, sp = rnd(30, 210)
            particles.append(P(x: x + cos(a) * d, y: y + sin(a) * d,
                               vx: cos(a) * sp + vx * 0.2,
                               vy: abs(sin(a)) * sp * 0.9 + 50 + max(0, vy) * 0.05,
                               size: rnd(1.4, 3.3)))
        }
        // a heap where it hit
        if let pile {
            let mh = pile.isGround ? maxH.ground : maxH.window
            let spread = r * 1.5
            for j in pile.index(x - spread)...pile.index(x + spread) {
                let cx = pile.rect.minX + (CGFloat(j) + 0.5) * Pile.col
                let f = max(0, 1 - abs(cx - x) / spread)
                pile.h[j] = min(pile.cap(j, mh * 1.8), pile.h[j] + r * 0.55 * f * f * (3 - 2 * f))
            }
        }
    }

    func burstSnowman(_ m: Snowman, onto pile: Pile? = nil) {
        guard !m.dead else { return }
        m.dead = true
        if heldMan === m { heldMan = nil }
        let cs = m.centres
        for (i, c) in cs.enumerated() {
            burst(x: c.x, y: c.y, r: m.r[i], vx: m.vx * 0.5, vy: m.vy * 0.5, onto: i == 0 ? pile : nil)
        }
        func debris(_ at: CGPoint, _ hue: Int, _ size: CGFloat) {
            var q = P(x: at.x, y: at.y, vx: rnd(-160, 160) + m.vx * 0.2, vy: rnd(120, 320), size: size,
                      maxLife: rnd(6, 9), hue: hue, kind: .debris)
            q.rot = rnd(0, .pi * 2); q.vrot = rnd(-10, 10)
            particles.append(q)
        }
        let head = cs[2], mid = cs[1]
        debris(CGPoint(x: head.x, y: head.y + m.r[2]), 1, m.r[2])            // hat
        debris(head, 0, m.r[2] * 0.8)                                         // carrot
        debris(CGPoint(x: mid.x - m.r[1], y: mid.y), 2, m.r[1] * 1.2)         // arms
        debris(CGPoint(x: mid.x + m.r[1], y: mid.y), 2, m.r[1] * 1.2)
        for _ in 0..<5 { debris(head, 3, max(1.5, m.r[2] * 0.09)) }           // coal
    }

    // MARK: drawing

    static let snowGrad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                 CGColor(red: 0.93, green: 0.95, blue: 1, alpha: 1),
                 CGColor(red: 0.72, green: 0.80, blue: 0.93, alpha: 1)] as CFArray,
        locations: [0, 0.55, 1])!

    func drawSnowSphere(_ c: CGContext, _ p: CGPoint, _ r: CGFloat, shadow: Bool = true) {
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        if shadow {
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -2), blur: 6,
                        color: CGColor(red: 0.1, green: 0.15, blue: 0.3, alpha: 0.4))
            c.setFillColor(CGColor(red: 0.85, green: 0.9, blue: 0.98, alpha: 1))
            c.fillEllipse(in: rect)
            c.restoreGState()
        }
        c.saveGState()
        c.addEllipse(in: rect); c.clip()
        c.drawRadialGradient(Simulation.snowGrad,
                             startCenter: CGPoint(x: p.x - r * 0.35, y: p.y + r * 0.4), startRadius: 0,
                             endCenter: p, endRadius: r * 1.08, options: [.drawsAfterEndLocation])
        c.restoreGState()
    }

    func drawBodies(_ c: CGContext) {
        for b in balls {
            drawSnowSphere(c, CGPoint(x: b.x, y: b.y), b.r)
            // a few packed-snow specks that roll with the ball
            c.setFillColor(CGColor(red: 0.75, green: 0.82, blue: 0.94, alpha: 0.7))
            for k in 0..<3 {
                let a = b.spin + CGFloat(k) * 2.1, d = b.r * (0.35 + 0.15 * CGFloat(k))
                let s = max(0.8, b.r * 0.07)
                c.fillEllipse(in: CGRect(x: b.x + cos(a) * d - s, y: b.y + sin(a) * d - s, width: s * 2, height: s * 2))
            }
        }
        for m in men { drawSnowman(c, m) }
    }

    func drawSnowman(_ c: CGContext, _ m: Snowman) {
        let lc = m.localCentres
        let r0 = m.r[0], r1 = m.r[1], r2 = m.r[2]
        let coal = CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        let wood = CGColor(red: 0.38, green: 0.23, blue: 0.12, alpha: 1)
        let red = CGColor(red: 0.84, green: 0.2, blue: 0.22, alpha: 1)
        c.saveGState()
        c.translateBy(x: m.x, y: m.y); c.rotate(by: m.tilt)

        // stick arms (behind the body)
        c.setStrokeColor(wood); c.setLineCap(.round); c.setLineWidth(max(1.5, r1 * 0.09))
        for side: CGFloat in [-1, 1] {
            let s = CGPoint(x: side * r1 * 0.6, y: lc[1].y + r1 * 0.15)
            let e = CGPoint(x: side * r1 * 1.95, y: lc[1].y + r1 * 0.95)
            c.move(to: s); c.addLine(to: e)
            let k = CGPoint(x: s.x + (e.x - s.x) * 0.72, y: s.y + (e.y - s.y) * 0.72)
            c.move(to: k); c.addLine(to: CGPoint(x: k.x + side * r1 * 0.2, y: k.y + r1 * 0.42))
            c.move(to: k); c.addLine(to: CGPoint(x: k.x + side * r1 * 0.45, y: k.y - r1 * 0.05))
        }
        c.strokePath()

        drawSnowSphere(c, lc[0], r0)
        drawSnowSphere(c, lc[1], r1)
        drawSnowSphere(c, lc[2], r2)

        // buttons
        c.setFillColor(coal)
        for k in -1...1 {
            let y = lc[1].y + CGFloat(k) * r1 * 0.42, s = max(1.2, r1 * 0.085)
            c.fillEllipse(in: CGRect(x: -s, y: y - s, width: s * 2, height: s * 2))
        }
        // scarf
        let scarfY = lc[2].y - r2 * 0.85
        c.setFillColor(red)
        c.addPath(CGPath(roundedRect: CGRect(x: -r2 * 0.95, y: scarfY - r2 * 0.16, width: r2 * 1.9, height: r2 * 0.34),
                         cornerWidth: r2 * 0.15, cornerHeight: r2 * 0.15, transform: nil))
        c.fillPath()
        c.addPath(CGPath(roundedRect: CGRect(x: r2 * 0.35, y: scarfY - r2 * 0.95, width: r2 * 0.3, height: r2 * 0.85),
                         cornerWidth: r2 * 0.1, cornerHeight: r2 * 0.1, transform: nil))
        c.fillPath()
        // face
        let h = lc[2]
        c.setFillColor(coal)
        for sx: CGFloat in [-1, 1] {
            let s = max(1.2, r2 * 0.1)
            c.fillEllipse(in: CGRect(x: h.x + sx * r2 * 0.33 - s, y: h.y + r2 * 0.22 - s, width: s * 2, height: s * 2))
        }
        for k in 0..<5 {
            let a = CGFloat.pi * (1.2 + 0.15 * CGFloat(k)), s = max(0.8, r2 * 0.055)
            c.fillEllipse(in: CGRect(x: h.x + cos(a) * r2 * 0.5 - s, y: h.y - r2 * 0.05 + sin(a) * r2 * 0.5 - s,
                                     width: s * 2, height: s * 2))
        }
        c.setFillColor(CGColor(red: 0.98, green: 0.55, blue: 0.15, alpha: 1))
        c.move(to: CGPoint(x: h.x, y: h.y + r2 * 0.06))
        c.addLine(to: CGPoint(x: h.x + r2 * 0.9, y: h.y - r2 * 0.06))
        c.addLine(to: CGPoint(x: h.x, y: h.y - r2 * 0.14))
        c.fillPath()
        // top hat
        c.saveGState()
        c.translateBy(x: h.x, y: h.y + r2 * 0.72); c.rotate(by: -0.12)
        c.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1))
        c.fill(CGRect(x: -r2 * 0.85, y: 0, width: r2 * 1.7, height: r2 * 0.14))
        c.fill(CGRect(x: -r2 * 0.55, y: r2 * 0.1, width: r2 * 1.1, height: r2 * 0.95))
        c.setFillColor(red)
        c.fill(CGRect(x: -r2 * 0.55, y: r2 * 0.14, width: r2 * 1.1, height: r2 * 0.16))
        c.restoreGState()

        c.restoreGState()
    }

    func drawDebris(_ c: CGContext, _ p: P) {
        let a = p.maxLife.isFinite ? clamp((p.maxLife - p.life) / 1.5, 0, 1) : 1
        c.saveGState()
        c.translateBy(x: p.x, y: p.y); c.rotate(by: p.rot); c.setAlpha(a)
        let s = p.size
        switch p.hue {
        case 0:
            c.setFillColor(CGColor(red: 0.98, green: 0.55, blue: 0.15, alpha: 1))
            c.move(to: CGPoint(x: -s * 0.5, y: s * 0.15)); c.addLine(to: CGPoint(x: s * 0.6, y: 0))
            c.addLine(to: CGPoint(x: -s * 0.5, y: -s * 0.15)); c.fillPath()
        case 1:
            c.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1))
            c.fill(CGRect(x: -s * 0.85, y: -s * 0.5, width: s * 1.7, height: s * 0.14))
            c.fill(CGRect(x: -s * 0.55, y: -s * 0.4, width: s * 1.1, height: s * 0.95))
            c.setFillColor(CGColor(red: 0.84, green: 0.2, blue: 0.22, alpha: 1))
            c.fill(CGRect(x: -s * 0.55, y: -s * 0.36, width: s * 1.1, height: s * 0.16))
        case 2:
            c.setStrokeColor(CGColor(red: 0.38, green: 0.23, blue: 0.12, alpha: 1))
            c.setLineWidth(max(1.5, s * 0.08)); c.setLineCap(.round)
            c.move(to: CGPoint(x: -s * 0.7, y: 0)); c.addLine(to: CGPoint(x: s * 0.7, y: 0))
            c.move(to: CGPoint(x: s * 0.25, y: 0)); c.addLine(to: CGPoint(x: s * 0.45, y: s * 0.3))
            c.strokePath()
        default:
            c.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1))
            c.fillEllipse(in: CGRect(x: -s, y: -s, width: s * 2, height: s * 2))
        }
        c.restoreGState()
    }
}
