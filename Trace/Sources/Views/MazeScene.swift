import SpriteKit
import SwiftUI

/// SpriteKit projector for one level. It renders the maze, follows the finger, and projects
/// the engine's trail as a glowing path. ALL game logic lives in `TraceEngine`; the scene
/// only maps touch → cell steps (with a forgiving corridor tolerance), plays the timed
/// hazards as functions of elapsed time, and animates the results.
private let kUnit: CGFloat = 64   // cell size in scene points

final class MazeScene: SKScene {

    // callbacks up to the view model
    var onStart: (() -> Void)?
    var onTrailChanged: ((_ backtracks: Int, _ resets: Int) -> Void)?
    var onTrapReset: (() -> Void)?
    var onWin: ((_ elapsed: Double, _ backtracks: Int, _ resets: Int) -> Void)?
    var onLiftReset: (() -> Void)?
    var reduceMotion = false

    private let maze: Maze
    private let theme: Theme
    private(set) var engine: TraceEngine

    private var tol: Double = 0.42            // corridor perpendicular tolerance (cells)

    // layers
    private let board = SKNode()
    private let cellLayer = SKNode()
    private let decorLayer = SKNode()
    private let dynamicLayer = SKNode()       // gates / movers / phantoms (time-driven)
    private let trailLayer = SKNode()

    private var trailGlow = SKShapeNode()
    private var trailMid = SKShapeNode()
    private var trailCore = SKShapeNode()
    private var head = SKNode()
    private var headTarget = CGPoint.zero        // live finger position the trail flows toward
    private var lastBuildHead = CGPoint(x: -1, y: -1)
    private var lastBuildCount = -1

    private var gateNodes: [(node: SKShapeNode, gate: Gate)] = []
    private var moverNodes: [(node: SKNode, hz: MovingHazard)] = []
    private var phantomNodes: [(node: SKShapeNode, ph: Phantom)] = []
    private var dimmable: [(node: SKNode, coord: Coord)] = []

    private var running = false
    private var runStart: TimeInterval = 0
    private var elapsed: Double = 0
    private var lastWallBuzz: TimeInterval = 0
    // After a trap snap-back, ignore further stepping until the finger comes back near the
    // checkpoint — otherwise a finger held past the hazard would re-trigger it every frame.
    private var awaitingRealign = false

    init(maze: Maze, theme: Theme, easier: Bool) {
        self.maze = maze
        self.theme = theme
        self.engine = TraceEngine(maze: maze)
        super.init(size: CGSize(width: CGFloat(maze.width) * kUnit, height: CGFloat(maze.height) * kUnit))
        // Slippery (glacier) levels are harder to keep centred in — a tighter corridor
        // tolerance, so the finger slips into walls more readily.
        self.tol = maze.slippery ? 0.32 : (easier ? 0.46 : 0.40)
        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = UIColor(theme.bg)
        addChild(board)
        board.addChild(cellLayer)
        board.addChild(decorLayer)
        board.addChild(dynamicLayer)
        board.addChild(trailLayer)
        buildBoard()
        buildTrailNodes()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: geometry

    private func center(_ c: Coord) -> CGPoint {
        CGPoint(x: (CGFloat(c.x) + 0.5) * kUnit, y: (CGFloat(c.y) + 0.5) * kUnit)
    }
    private func pointToCellF(_ p: CGPoint) -> (x: Double, y: Double) {
        (Double(p.x / kUnit) - 0.5, Double(p.y / kUnit) - 0.5)
    }

    // MARK: build static board

    private func buildBoard() {
        // corridor tiles (also the fog-dimmable surface)
        for x in 0..<maze.width { for y in 0..<maze.height {
            let c = Coord(x, y)
            let r = SKShapeNode(rect: CGRect(x: center(c).x - kUnit/2 + 2, y: center(c).y - kUnit/2 + 2,
                                             width: kUnit - 4, height: kUnit - 4), cornerRadius: 6)
            r.fillColor = UIColor(theme.corridor); r.strokeColor = .clear
            cellLayer.addChild(r)
            dimmable.append((r, c))
        }}

        // walls — draw each wall once (north + east everywhere, south/west only on the border)
        let wallPath = CGMutablePath()
        func seg(_ a: CGPoint, _ b: CGPoint) { wallPath.move(to: a); wallPath.addLine(to: b) }
        for x in 0..<maze.width { for y in 0..<maze.height {
            let c = Coord(x, y)
            let bx = CGFloat(x) * kUnit, by = CGFloat(y) * kUnit
            if !maze.isOpen(c, .north) { seg(CGPoint(x: bx, y: by + kUnit), CGPoint(x: bx + kUnit, y: by + kUnit)) }
            if !maze.isOpen(c, .east)  { seg(CGPoint(x: bx + kUnit, y: by), CGPoint(x: bx + kUnit, y: by + kUnit)) }
            if y == 0, !maze.isOpen(c, .south) { seg(CGPoint(x: bx, y: by), CGPoint(x: bx + kUnit, y: by)) }
            if x == 0, !maze.isOpen(c, .west)  { seg(CGPoint(x: bx, y: by), CGPoint(x: bx, y: by + kUnit)) }
        }}
        let glow = SKShapeNode(path: wallPath)
        glow.strokeColor = UIColor(theme.wall); glow.lineWidth = kUnit * 0.30
        glow.lineCap = .round; glow.alpha = 0.35; glow.glowWidth = kUnit * 0.10
        let walls = SKShapeNode(path: wallPath)
        walls.strokeColor = UIColor(theme.wall); walls.lineWidth = kUnit * 0.14; walls.lineCap = .round
        cellLayer.addChild(glow); cellLayer.addChild(walls)

        // decorations
        addStart()
        addGoal()
        for cp in maze.checkpoints { addCheckpoint(cp) }
        for s in maze.spikes { addSpike(s) }
        for ow in maze.oneWays { addOneWay(ow) }

        // dynamic (time-driven)
        for g in maze.gates { addGate(g) }
        for hz in maze.moving { addMover(hz) }
        for ph in maze.phantoms { addPhantom(ph) }
    }

    private func ring(_ c: Coord, color: Color, r: CGFloat, line: CGFloat) -> SKShapeNode {
        let n = SKShapeNode(circleOfRadius: r)
        n.position = center(c); n.strokeColor = UIColor(color); n.lineWidth = line
        n.fillColor = .clear; n.glowWidth = line * 0.8
        return n
    }

    private func addStart() {
        let n = ring(Coord(maze.start.x, maze.start.y), color: theme.accent, r: kUnit * 0.30, line: kUnit * 0.07)
        n.fillColor = UIColor(theme.accent).withAlphaComponent(0.18)
        decorLayer.addChild(n); dimmable.append((n, maze.start))
        let label = SKLabelNode(text: "start"); label.fontName = "AvenirNext-DemiBold"
        label.fontSize = kUnit * 0.20; label.fontColor = UIColor(theme.accentHi)
        label.position = CGPoint(x: center(maze.start).x, y: center(maze.start).y - kUnit * 0.04)
        label.verticalAlignmentMode = .center; decorLayer.addChild(label)
    }

    private func addGoal() {
        let outer = ring(maze.goal, color: Theme.goalRing, r: kUnit * 0.34, line: kUnit * 0.08)
        let inner = SKShapeNode(circleOfRadius: kUnit * 0.14)
        inner.position = center(maze.goal); inner.fillColor = UIColor(Theme.goalRing)
        inner.strokeColor = .clear; inner.glowWidth = kUnit * 0.12
        decorLayer.addChild(outer); decorLayer.addChild(inner)
        dimmable.append((outer, maze.goal))
        if !reduceMotion {
            outer.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.8), .scale(to: 1.0, duration: 0.8)])))
        }
    }

    private func addCheckpoint(_ c: Coord) {
        let n = ring(c, color: Theme.checkpoint, r: kUnit * 0.22, line: kUnit * 0.055)
        decorLayer.addChild(n); dimmable.append((n, c))
    }

    private func addSpike(_ c: Coord) {
        // a four-point danger star
        let path = CGMutablePath()
        let R = kUnit * 0.26, rr = kUnit * 0.10, cx = center(c).x, cy = center(c).y
        for i in 0..<8 {
            let ang = CGFloat(i) * .pi / 4
            let rad = i % 2 == 0 ? R : rr
            let p = CGPoint(x: cx + cos(ang) * rad, y: cy + sin(ang) * rad)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        let n = SKShapeNode(path: path)
        n.fillColor = UIColor(Theme.danger).withAlphaComponent(0.85)
        n.strokeColor = UIColor(Theme.danger); n.lineWidth = 1.5; n.glowWidth = kUnit * 0.05
        decorLayer.addChild(n); dimmable.append((n, c))
        if !reduceMotion {
            n.run(.repeatForever(.sequence([.rotate(byAngle: .pi/2, duration: 2.2)])))
        }
    }

    private func addOneWay(_ ow: OneWay) {
        let mid = CGPoint(x: (center(ow.from).x + center(ow.to).x) / 2,
                          y: (center(ow.from).y + center(ow.to).y) / 2)
        let dir = atan2(center(ow.to).y - center(ow.from).y, center(ow.to).x - center(ow.from).x)
        let path = CGMutablePath()
        let L = kUnit * 0.16
        path.move(to: CGPoint(x: -L, y: -L)); path.addLine(to: CGPoint(x: L, y: 0)); path.addLine(to: CGPoint(x: -L, y: L))
        let n = SKShapeNode(path: path)
        n.strokeColor = UIColor(theme.accentHi); n.lineWidth = kUnit * 0.05; n.lineJoin = .round
        n.glowWidth = kUnit * 0.04; n.position = mid; n.zRotation = dir
        decorLayer.addChild(n)
    }

    private func addGate(_ g: Gate) {
        let mid = CGPoint(x: (center(g.a).x + center(g.b).x) / 2, y: (center(g.a).y + center(g.b).y) / 2)
        let horizontalEdge = g.a.y == g.b.y      // a,b side-by-side → bar is vertical
        let w = horizontalEdge ? kUnit * 0.16 : kUnit * 0.66
        let h = horizontalEdge ? kUnit * 0.66 : kUnit * 0.16
        let n = SKShapeNode(rect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerRadius: kUnit * 0.05)
        n.position = mid; n.glowWidth = kUnit * 0.05
        dynamicLayer.addChild(n)
        gateNodes.append((n, g))
    }

    private func addMover(_ hz: MovingHazard) {
        let n = SKShapeNode(circleOfRadius: kUnit * 0.22)
        n.fillColor = UIColor(Theme.moving); n.strokeColor = UIColor(Theme.goalRing)
        n.lineWidth = 2; n.glowWidth = kUnit * 0.14
        n.position = center(hz.cell(at: 0))
        dynamicLayer.addChild(n)
        moverNodes.append((n, hz))
    }

    private func addPhantom(_ ph: Phantom) {
        let n = SKShapeNode(rect: CGRect(x: center(ph.cell).x - kUnit/2 + 4, y: center(ph.cell).y - kUnit/2 + 4,
                                         width: kUnit - 8, height: kUnit - 8), cornerRadius: 6)
        n.strokeColor = UIColor(theme.accentHi).withAlphaComponent(0.6); n.lineWidth = 2
        n.fillColor = UIColor(theme.accentHi).withAlphaComponent(0.10)
        dynamicLayer.addChild(n)
        phantomNodes.append((n, ph))
        // NOT added to `dimmable`: its alpha is state-driven (solid/blink); fog is composed in
        // update() so the two don't fight.
    }

    private func buildTrailNodes() {
        // Glow is faked by stacking three solid strokes (wide+faint → mid → bright core). We do
        // NOT use SKShapeNode.glowWidth: on a thick, frequently-redrawn stroked path it produces
        // triangular tessellation spikes ("shredding" along the line). Round joins soften corners.
        for (n, w, a, c): (SKShapeNode, CGFloat, CGFloat, Color) in [
            (trailGlow, kUnit * 0.64, 0.16, theme.glow),
            (trailMid,  kUnit * 0.34, 0.80, theme.accent),
            (trailCore, kUnit * 0.13, 1.0,  theme.accentHi),
        ] {
            n.strokeColor = UIColor(c).withAlphaComponent(a); n.lineWidth = w
            n.lineCap = .round; n.lineJoin = .round; n.fillColor = .clear
            n.glowWidth = 0
            n.isAntialiased = true
            trailLayer.addChild(n)
        }
        // finger head
        let h1 = SKShapeNode(circleOfRadius: kUnit * 0.22)
        h1.fillColor = UIColor(theme.glow).withAlphaComponent(0.35); h1.strokeColor = .clear; h1.glowWidth = kUnit * 0.12
        let h2 = SKShapeNode(circleOfRadius: kUnit * 0.11)
        h2.fillColor = UIColor(theme.accentHi); h2.strokeColor = .clear
        head.addChild(h1); head.addChild(h2)
        head.position = center(maze.start)
        headTarget = center(maze.start)
        trailLayer.addChild(head)
        rebuildTrail(force: true)
    }

    /// Rebuild the glowing trail: the recorded cell-centre path PLUS a live leading segment to
    /// the finger, smoothed so corners flow instead of cornering at hard right angles. Cheap to
    /// call per touch sample; skips when nothing moved.
    private func rebuildTrail(force: Bool = false) {
        guard !engine.trail.isEmpty else { return }
        if !force, engine.trail.count == lastBuildCount,
           hypot(headTarget.x - lastBuildHead.x, headTarget.y - lastBuildHead.y) < 0.6 { return }

        var pts = engine.trail.map { center($0) }
        // extend to the live finger so the line grows smoothly, not a cell at a time — but only
        // when the finger is genuinely AHEAD of the last cell, so it never doubles back (which a
        // thick stroke renders as a barb).
        if running, !awaitingRealign, let last = pts.last,
           hypot(headTarget.x - last.x, headTarget.y - last.y) > 0.5 {
            if pts.count >= 2 {
                let prev = pts[pts.count - 2]
                let forward = (last.x - prev.x) * (headTarget.x - last.x) + (last.y - prev.y) * (headTarget.y - last.y)
                if forward > 0 { pts.append(headTarget) }
            } else {
                pts.append(headTarget)
            }
        }
        let path = smoothedPath(pts)
        trailGlow.path = path; trailMid.path = path; trailCore.path = path
        head.position = (running && !awaitingRealign) ? headTarget : center(engine.current)
        lastBuildHead = headTarget; lastBuildCount = engine.trail.count
    }

    /// A plain polyline through the trail points. Corners are softened by the strokes' round
    /// lineJoin (radius ≈ width/2) — clean and artifact-free, vs. hand-rolled curves which left
    /// near-degenerate segments at the moving leading edge.
    private func smoothedPath(_ p: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = p.first else { return path }
        path.move(to: first)
        for q in p.dropFirst() { path.addLine(to: q) }
        return path
    }

    // MARK: touch → cell stepping

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, engine.status == .tracing else { return }
        let f = pointToCellF(t.location(in: self))
        // must begin on (or very near) the start cell
        guard abs(f.x - Double(maze.start.x)) < 0.7, abs(f.y - Double(maze.start.y)) < 0.7 else { return }
        if !running { startRun() }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard running, engine.status == .tracing, let t = touches.first else { return }
        let f = pointToCellF(t.location(in: self))
        // after a trap snap-back, wait until the finger is back near the checkpoint before
        // resuming — prevents re-triggering the hazard while the finger is still past it.
        if awaitingRealign {
            let cur = engine.current
            if abs(f.x - Double(cur.x)) <= 0.7 && abs(f.y - Double(cur.y)) <= 0.7 { awaitingRealign = false }
            else { head.position = fingerClamp(f); return }
        }
        step(toward: f)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { liftReset() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { liftReset() }

    private func startRun() {
        running = true
        runStart = CACurrentMediaTime()
        elapsed = 0
        awaitingRealign = false
        onStart?()
    }

    /// Reset to the start for a fresh attempt (the "retry" button).
    func restart() {
        running = false
        awaitingRealign = false
        engine.reset()
        headTarget = center(maze.start)
        rebuildTrail(force: true)
        for (node, _) in dimmable { node.alpha = 1 }
        applyFog()
    }

    /// The final start→goal trail as [x,y] pairs, for leaderboard submission.
    var trailPairs: [[Int]] { engine.trail.map { [$0.x, $0.y] } }

    /// Lifting the finger before the goal resets the trace to the start (blueprint §2/§8).
    private func liftReset() {
        guard running, engine.status == .tracing else { return }
        running = false
        awaitingRealign = false
        engine.reset()
        headTarget = center(maze.start)
        rebuildTrail(force: true)
        applyFog()
        onLiftReset?()
        Haptics.backtrack()
    }

    /// Step the engine one cell at a time toward the finger, up to a few cells so a fast drag
    /// doesn't skip corridors. Tries the dominant axis first, then the other — so a corner
    /// turn isn't refused just because the first post-bend sample is off the new corridor's
    /// centreline. Honours the perpendicular corridor tolerance on whichever axis it takes.
    private func step(toward f: (x: Double, y: Double)) {
        for _ in 0..<6 {
            let cur = engine.current
            let dx = f.x - Double(cur.x)
            let dy = f.y - Double(cur.y)
            if abs(dx) <= 0.5 && abs(dy) <= 0.5 { break }                  // finger within current cell

            let horizontal = abs(dx) >= abs(dy)
            var moved = false
            var blocked = false
            for h in (horizontal ? [true, false] : [false, true]) {
                let along = h ? dx : dy
                let perp  = h ? dy : dx
                guard abs(along) > 0.5, abs(perp) <= tol else { continue } // not a valid crossing on this axis
                let dir: Direction = h ? (along > 0 ? .east : .west) : (along > 0 ? .north : .south)
                switch engine.move(to: maze.neighbor(cur, dir), at: currentElapsed()) {
                case .advanced(let c):
                    if maze.checkpoints.contains(c) { Haptics.checkpoint(); checkpointPulse(c) } else { Haptics.step() }
                    notifyTrail(); moved = true                           // trail redrawn at end of step()
                case .backtracked:
                    Haptics.backtrack(); notifyTrail(); moved = true
                case .reset:
                    Haptics.trap(); flashTrap()
                    awaitingRealign = true                                 // stop until the finger comes back
                    headTarget = center(engine.current)                   // snap the head to the checkpoint
                    rebuildTrail(force: true); notifyTrail(); onTrapReset?()
                    return
                case .reachedGoal:
                    let t = currentElapsed(); running = false; elapsed = t // capture BEFORE clearing running
                    headTarget = center(engine.current)                   // = goal
                    Haptics.goal(); rebuildTrail(force: true); winBurst()
                    onWin?(t, engine.backtrackCount, engine.resetCount); return
                case .blockedByWall, .blockedByGate, .blockedOneWay:
                    blocked = true; continue                              // try the other axis before buzzing
                case .ignored:
                    continue
                }
                break                                                     // acted on this axis; re-evaluate
            }
            if !moved { if blocked { buzzWall() }; break }
        }
        headTarget = fingerClamp(f)
        rebuildTrail()            // flow the leading edge to the finger every touch sample
    }

    private func notifyTrail() { onTrailChanged?(engine.backtrackCount, engine.resetCount) }

    /// Visually pin the head no more than ~0.5 cell outside the current cell, so a finger
    /// pressed against a wall shows the trail held at the wall (not floating into it).
    private func fingerClamp(_ f: (x: Double, y: Double)) -> CGPoint {
        let cur = engine.current
        let cx = min(Double(cur.x) + 0.5, max(Double(cur.x) - 0.5, f.x))
        let cy = min(Double(cur.y) + 0.5, max(Double(cur.y) - 0.5, f.y))
        return CGPoint(x: (cx + 0.5) * Double(kUnit), y: (cy + 0.5) * Double(kUnit))
    }

    private func currentElapsed() -> Double {
        running ? CACurrentMediaTime() - runStart : elapsed
    }

    private func buzzWall() {
        let now = CACurrentMediaTime()
        guard now - lastWallBuzz > 0.12 else { return }
        lastWallBuzz = now
        Haptics.wall()
        if !reduceMotion {
            trailLayer.run(.sequence([.moveBy(x: 3, y: 0, duration: 0.03), .moveBy(x: -6, y: 0, duration: 0.03),
                                      .moveBy(x: 3, y: 0, duration: 0.03)]))
        }
    }

    private func checkpointPulse(_ c: Coord) {
        guard !reduceMotion else { return }
        let p = SKShapeNode(circleOfRadius: kUnit * 0.18)
        p.position = center(c); p.strokeColor = UIColor(Theme.checkpoint); p.lineWidth = 3; p.fillColor = .clear
        decorLayer.addChild(p)
        p.run(.sequence([.group([.scale(to: 2.2, duration: 0.4), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
    }

    private func flashTrap() {
        let flash = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        flash.fillColor = UIColor(Theme.danger); flash.strokeColor = .clear; flash.alpha = 0; flash.zPosition = 80
        addChild(flash)
        flash.run(.sequence([.fadeAlpha(to: 0.28, duration: 0.06), .fadeOut(withDuration: 0.32), .removeFromParent()]))
    }

    private func winBurst() {
        guard !reduceMotion else { return }
        let p = center(maze.goal)
        for _ in 0..<20 {
            let s = SKShapeNode(circleOfRadius: kUnit * 0.06)
            s.fillColor = UIColor(Theme.goalRing); s.strokeColor = .clear; s.position = p; s.zPosition = 90
            addChild(s)
            let ang = CGFloat.random(in: 0..<(.pi * 2)), dist = CGFloat.random(in: kUnit*0.5...kUnit*1.4)
            s.run(.sequence([.group([.move(by: CGVector(dx: cos(ang)*dist, dy: sin(ang)*dist), duration: 0.5),
                                     .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        }
    }

    // MARK: per-frame (timed hazards + fog)

    override func update(_ currentTime: TimeInterval) {
        let t = currentElapsed()
        for (node, g) in gateNodes {
            let open = g.isOpen(at: t)
            node.fillColor = UIColor(open ? Theme.gateOpen : Theme.danger).withAlphaComponent(open ? 0.35 : 0.95)
            node.strokeColor = UIColor(open ? Theme.gateOpen : Theme.danger)
            node.lineWidth = open ? 1 : 2
            // compose the open/closed alpha with fog so a gate doesn't leak its state through fog
            node.alpha = (open ? 0.5 : 1.0) * max(fogFactor(g.a), fogFactor(g.b))
            // a thin sliver of "time left" feel: scale the bar down a touch as it nears closing
            let phase = g.phaseValue(at: t)
            let closing = phase > g.openFraction * 0.7 && phase < g.openFraction
            node.setScale(open ? (closing ? 0.8 : 1.0) : 1.0)
        }
        for (node, hz) in moverNodes {
            let c = hz.cell(at: t)
            node.position = center(c)
            node.alpha = fogFactor(c)
        }
        for (node, ph) in phantomNodes {
            let solid = ph.isSolid(at: t)
            node.alpha = (solid ? 1 : 0.12) * fogFactor(ph.cell)     // state × fog (don't overwrite state)
            node.fillColor = UIColor(solid ? theme.corridor : Theme.danger).withAlphaComponent(solid ? 1 : 0.12)
            node.strokeColor = UIColor(solid ? theme.accentHi : Theme.danger).withAlphaComponent(solid ? 0.5 : 0.4)
        }
        applyFog()
    }

    /// Visibility multiplier for a cell under fog-of-war (1 = lit, →0 = hidden); 1 everywhere
    /// when the level has no fog.
    private func fogFactor(_ c: Coord) -> CGFloat {
        guard let r = maze.fogRadius else { return 1 }
        let d = max(abs(c.x - engine.current.x), abs(c.y - engine.current.y))
        return d <= r ? 1.0 : (d <= r + 1 ? 0.32 : 0.08)
    }

    private func applyFog() {
        guard maze.fogRadius != nil else { return }
        for (node, c) in dimmable { node.alpha = fogFactor(c) }
    }
}
