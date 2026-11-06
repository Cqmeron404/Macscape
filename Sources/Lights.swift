// Macscapes — green-corded Christmas lights the user hangs wherever they want.
//
//   • ⌥-drag across empty space to string lights between two points.
//   • The cord hangs as one natural droop; it swings, sways in the wind and settles (verlet rope).
//   • ⌥-drag an attach point (a nail) to move it.  ⌥-click the cord to pin a new attach point there —
//     that is how you make even, evenly-spaced swags: you place the nails yourself.
//   • ⌥-click a nail to remove it (removing an end nail removes the whole string); or Clear from the menu.
//
// Drawn by the FRONT overlay, so the lights show over windows, not just on the desktop.

import Cocoa

/// A string of lights: user-placed attach points, plus a simulated cord (verlet nodes) between them.
struct LightString {
    var anchors: [CGPoint]              // pinned attach points, in order (≥2)
    var nodes: [CGPoint] = []           // simulated cord points
    var prev: [CGPoint] = []            // previous positions (verlet integration)
    var anchorOf: [Int] = []            // node → anchor index it's pinned to, or -1 if free
    var seed: CGFloat
    var hueOffset: Int
    var lightSnow: CGFloat = 0
    static let seg: CGFloat = 9         // cord node spacing (rest length)

    init(anchors: [CGPoint], seed: CGFloat, hueOffset: Int) {
        self.anchors = anchors; self.seed = seed; self.hueOffset = hueOffset
        rebuild()
    }

    /// Lay out the cord along the anchors with enough slack to droop, starting pre-sagged.
    mutating func rebuild() {
        nodes = []; anchorOf = []
        let sag: CGFloat = 1.3
        for i in 0..<(anchors.count - 1) {
            let a = anchors[i], b = anchors[i + 1]
            let d = max(1, hypot(b.x - a.x, b.y - a.y))
            let count = max(2, Int((d * sag) / LightString.seg))
            for k in 0..<count {
                if i > 0 && k == 0 { continue }         // shared anchor node already present
                let t = CGFloat(k) / CGFloat(count - 1)
                let x = a.x + (b.x - a.x) * t
                let y = a.y + (b.y - a.y) * t - sin(t * .pi) * d * 0.22
                nodes.append(CGPoint(x: x, y: y))
                anchorOf.append(k == 0 ? i : (k == count - 1 ? i + 1 : -1))
            }
        }
        prev = nodes
    }

    mutating func step(dt: CGFloat, gravity: CGFloat, windX: CGFloat) {
        guard nodes.count > 1 else { return }
        for n in nodes.indices {
            if anchorOf[n] >= 0 { nodes[n] = anchors[anchorOf[n]]; prev[n] = nodes[n]; continue }
            let vx = (nodes[n].x - prev[n].x) * 0.985
            let vy = (nodes[n].y - prev[n].y) * 0.985
            prev[n] = nodes[n]
            nodes[n].x += vx + windX * dt * dt
            nodes[n].y += vy - gravity * dt * dt
        }
        for _ in 0..<5 {
            for s in 0..<(nodes.count - 1) {
                let pinA = anchorOf[s] >= 0, pinB = anchorOf[s + 1] >= 0
                let dx = nodes[s + 1].x - nodes[s].x, dy = nodes[s + 1].y - nodes[s].y
                let d = max(0.001, hypot(dx, dy))
                let diff = (d - LightString.seg) / d
                let mA: CGFloat = pinA ? 0 : (pinB ? 1 : 0.5)
                let mB: CGFloat = pinB ? 0 : (pinA ? 1 : 0.5)
                nodes[s].x += dx * diff * mA;     nodes[s].y += dy * diff * mA
                nodes[s + 1].x -= dx * diff * mB; nodes[s + 1].y -= dy * diff * mB
            }
            for n in nodes.indices where anchorOf[n] >= 0 { nodes[n] = anchors[anchorOf[n]] }
        }
    }

    /// Insert a new attach point at p, on the span nearest to it; returns the new anchor's index.
    mutating func pin(at p: CGPoint) -> Int {
        var best = (span: 0, dist: CGFloat.greatestFiniteMagnitude)
        for i in 0..<(anchors.count - 1) {
            let d = Simulation.segDist(p, anchors[i], anchors[i + 1])
            if d < best.dist { best = (i, d) }
        }
        let idx = best.span + 1
        anchors.insert(p, at: idx)
        rebuild()
        return idx
    }
}

extension Simulation {
    static let bulbCols: [CGColor] = [
        CGColor(red: 0.95, green: 0.22, blue: 0.22, alpha: 1),   // red
        CGColor(red: 0.30, green: 0.80, blue: 0.35, alpha: 1),   // green
        CGColor(red: 0.30, green: 0.55, blue: 0.98, alpha: 1),   // blue
        CGColor(red: 0.98, green: 0.78, blue: 0.28, alpha: 1),   // amber
        CGColor(red: 0.92, green: 0.45, blue: 0.85, alpha: 1),   // pink
    ]
    static let cord = CGColor(red: 0.16, green: 0.42, blue: 0.20, alpha: 1)
    static let cordLit = CGColor(red: 0.22, green: 0.52, blue: 0.26, alpha: 1)

    static func segDist(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
        if len2 < 1 { return hypot(p.x - a.x, p.y - a.y) }
        let t = clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0, 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    // MARK: placement & dragging

    func addDefaultLightString() {
        let y = bounds.maxY * 0.62
        lightStrings.append(LightString(anchors: [CGPoint(x: bounds.width * 0.32, y: y),
                                                  CGPoint(x: bounds.width * 0.68, y: y)],
                                        seed: rnd(0, 100), hueOffset: Int.random(in: 0...4)))
    }

    private func cordDist(_ p: CGPoint, _ s: LightString) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        for i in 0..<(s.nodes.count - 1) { best = min(best, Simulation.segDist(p, s.nodes[i], s.nodes[i + 1])) }
        return best
    }

    func lightMouse(global: CGPoint, phase: Int, option: Bool) {
        let p = CGPoint(x: global.x - frame.minX, y: global.y - frame.minY)
        switch phase {
        case 0:   // mouse down
            guard option, bounds.insetBy(dx: 40, dy: 40).contains(p) else { return }
            dragMoved = false
            // grab an existing attach point?
            for (si, s) in lightStrings.enumerated() {
                for (ai, a) in s.anchors.enumerated() where hypot(a.x - p.x, a.y - p.y) < 16 {
                    dragAnchor = (si, ai); return
                }
            }
            // click on a cord → pin a new attach point there, and start dragging it
            for (si, s) in lightStrings.enumerated() where s.nodes.count > 1 {
                if cordDist(p, s) < 12 {
                    let ai = lightStrings[si].pin(at: p)
                    dragAnchor = (si, ai); return
                }
            }
            // over fallen snow, leave the gesture to the snowball tool
            if effect == .snow {
                for pile in order where !pile.isGround && p.x > pile.rect.minX && p.x < pile.rect.maxX {
                    if pile.height(at: p.x) > 1, p.y < pile.base(p.x) + pile.height(at: p.x) + 20 { return }
                }
            }
            drawingLight = (a: p, b: p)
        case 1:   // dragging
            if let d = dragAnchor, d.s < lightStrings.count, d.a < lightStrings[d.s].anchors.count {
                lightStrings[d.s].anchors[d.a] = p
                dragMoved = true
            } else if drawingLight != nil {
                drawingLight!.b = p
            }
        default:  // mouse up
            if let d = dragAnchor {
                if d.s < lightStrings.count {
                    if dragMoved {
                        lightStrings[d.s].rebuild()                 // normalise slack after moving
                    } else if d.a == 0 || d.a == lightStrings[d.s].anchors.count - 1 {
                        lightStrings.remove(at: d.s)                // clicked an end nail → remove string
                    } else {
                        lightStrings[d.s].anchors.remove(at: d.a)   // clicked a middle nail → unpin it
                        lightStrings[d.s].rebuild()
                    }
                }
                dragAnchor = nil
            } else if let s = drawingLight {
                if hypot(s.b.x - s.a.x, s.b.y - s.a.y) > 24 {
                    lightStrings.append(LightString(anchors: [s.a, s.b],
                                                    seed: rnd(0, 100), hueOffset: Int.random(in: 0...4)))
                }
                drawingLight = nil
            }
        }
    }

    func stepLights(_ dt: CGFloat) {
        let windX = (sin(time * 0.9) * 120 + sin(time * 2.3) * 50) * windK + slant * 220 * windK
        for i in lightStrings.indices {
            lightStrings[i].step(dt: dt, gravity: 1500, windX: windX)
            if effect == .snow { lightStrings[i].lightSnow = min(1, lightStrings[i].lightSnow + 0.05 * dt) }
            else { lightStrings[i].lightSnow = max(0, lightStrings[i].lightSnow - 0.15 * dt) }
        }
    }

    // MARK: drawing

    func drawLights(_ c: CGContext) {
        for s in lightStrings { drawString(c, s) }
        if let d = drawingLight {                                   // live preview while dragging a new one
            c.setStrokeColor(Simulation.cord); c.setLineWidth(1.6); c.setLineCap(.round)
            let mid = CGPoint(x: (d.a.x + d.b.x) / 2, y: min(d.a.y, d.b.y) - 24)
            c.move(to: d.a); c.addQuadCurve(to: d.b, control: mid); c.strokePath()
            for pt in [d.a, d.b] {
                c.setFillColor(CGColor(red: 0.26, green: 0.26, blue: 0.28, alpha: 1))
                c.fillEllipse(in: CGRect(x: pt.x - 2.3, y: pt.y - 2.3, width: 4.6, height: 4.6))
            }
        }
    }

    private func drawString(_ c: CGContext, _ s: LightString) {
        guard s.nodes.count > 1 else { return }
        let snow = s.lightSnow
        // cord
        let cord = CGMutablePath(); cord.addLines(between: s.nodes)
        c.setStrokeColor(snow > 0.05 ? Simulation.cordLit : Simulation.cord)
        c.setLineWidth(1.6); c.setLineCap(.round); c.setLineJoin(.round)
        c.addPath(cord); c.strokePath()
        if snow > 0.05 {
            c.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5 * snow))
            c.setLineWidth(1.0); c.addPath(cord); c.strokePath()
        }
        // bulbs every other node, hanging just under the cord
        var bulbIndex = s.hueOffset
        var k = 1
        while k < s.nodes.count {
            let n = s.nodes[k]
            let col = Simulation.bulbCols[bulbIndex % Simulation.bulbCols.count]
            bulbIndex += 1
            let twinkle = 0.55 + 0.45 * pow(0.5 + 0.5 * sin(time * 2.0 + CGFloat(bulbIndex) * 1.3 + s.seed), 1.5)
            let bc = CGPoint(x: n.x, y: n.y - 5)
            c.setStrokeColor(Simulation.cord); c.setLineWidth(1)
            c.move(to: n); c.addLine(to: CGPoint(x: bc.x, y: bc.y + 2)); c.strokePath()
            drawBulb(c, bc, col: col, glow: twinkle)
            if snow > 0.1 {
                c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
                c.fillEllipse(in: CGRect(x: bc.x - 2.6, y: bc.y + 1.4, width: 5.2, height: 2.2 * snow + 1.4))
            }
            k += 2
        }
        // attach nails
        for a in s.anchors {
            c.setFillColor(CGColor(red: 0.26, green: 0.26, blue: 0.28, alpha: 1))
            c.fillEllipse(in: CGRect(x: a.x - 2.3, y: a.y - 2.3, width: 4.6, height: 4.6))
        }
    }

    private func drawBulb(_ c: CGContext, _ p: CGPoint, col: CGColor, glow: CGFloat) {
        let r: CGFloat = 3.4
        func circle(_ rad: CGFloat, _ color: CGColor) {
            c.setFillColor(color)
            c.fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2))
        }
        circle(r * 2.6, col.copy(alpha: 0.12 * glow)!)
        circle(r * 1.7, col.copy(alpha: 0.22 * glow)!)
        circle(r, col.copy(alpha: 0.65 + 0.35 * glow)!)
        circle(r * 0.5, CGColor(red: 1, green: 1, blue: 1, alpha: 0.35 + 0.5 * glow))
        c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9 * glow))
        c.fillEllipse(in: CGRect(x: p.x - 0.7, y: p.y + 0.4, width: 1.4, height: 1.4))
        c.setFillColor(Simulation.cord)
        c.fill(CGRect(x: p.x - 1.3, y: p.y + r - 0.5, width: 2.6, height: 1.6))
    }
}
