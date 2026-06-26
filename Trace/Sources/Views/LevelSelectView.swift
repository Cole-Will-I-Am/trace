import SwiftUI

/// The 21-level gallery. Each card shows a live thumbnail of the actual maze, its theme
/// colour, stars earned, and your best time. Levels unlock in sequence.
struct LevelSelectView: View {
    @ObservedObject var progress: Progress
    @ObservedObject var account: Account
    let onPlay: (Int) -> Void

    @State private var showLeaderboard = false
    @State private var showHowTo = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Levels.all, id: \.id) { spec in
                        LevelCard(spec: spec, record: progress.record(spec.id),
                                  locked: !progress.isUnlocked(spec.id))
                            .onTapGesture { if progress.isUnlocked(spec.id) { Haptics.tap(); onPlay(spec.id) } }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
        }
        .background(Theme.ink.ignoresSafeArea())
        .sheet(isPresented: $showLeaderboard) { LeaderboardView(account: account, progress: progress) }
        .sheet(isPresented: $showHowTo) { HowToPlayView() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text("TRACE").font(Typeface.display(34, .heavy)).foregroundStyle(Theme.onInk)
                    .tracking(4)
                Spacer()
                Button { showHowTo = true } label: {
                    Image(systemName: "questionmark.circle").font(.system(size: 22)).foregroundStyle(Theme.onInkDim)
                }
                Button { showLeaderboard = true } label: {
                    Image(systemName: "trophy").font(.system(size: 20)).foregroundStyle(Theme.goalRing)
                }
            }
            HStack(spacing: 16) {
                pill(icon: "star.fill", text: "\(progress.totalStars)/\(Levels.count * 3)", tint: Theme.goalRing)
                pill(icon: "flag.checkered", text: "\(progress.completedCount)/\(Levels.count)", tint: Theme.checkpoint)
                if let total = progress.totalBestMs {
                    pill(icon: "clock", text: total.asClock, tint: Theme.onInk)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    private func pill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12))
            Text(text).font(Typeface.mono(13, .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Theme.inkRaised))
    }
}

private struct LevelCard: View {
    let spec: LevelSpec
    let record: LevelRecord
    let locked: Bool

    private var theme: Theme { Theme.of(spec.theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                MazeThumbnail(maze: Levels.maze(spec.id), theme: theme)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .saturation(locked ? 0 : 1).opacity(locked ? 0.5 : 1)
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.onInkDim)
                }
                VStack { Spacer(); HStack {
                    Text("\(spec.id)").font(Typeface.display(15, .heavy)).foregroundStyle(theme.bg)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(theme.accent)).padding(6)
                    Spacer()
                } }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(spec.title).font(Typeface.display(14, .semibold)).foregroundStyle(Theme.onInk)
                    .lineLimit(1)
                HStack {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: i < record.stars ? "star.fill" : "star")
                                .font(.system(size: 9)).foregroundStyle(i < record.stars ? Theme.goalRing : Theme.onInkDim.opacity(0.5))
                        }
                    }
                    Spacer()
                    Text(record.bestTimeMs?.asClock ?? difficulty)
                        .font(Typeface.mono(11, .medium)).foregroundStyle(Theme.onInkDim)
                }
            }
            .padding(.horizontal, 4).padding(.top, 7)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.inkRaised))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.accent.opacity(locked ? 0.0 : 0.18), lineWidth: 1))
    }

    private var difficulty: String { String(repeating: "★", count: spec.stars) }
}

/// A small SwiftUI Canvas render of a real maze — walls + start/goal, in the level's palette.
struct MazeThumbnail: View {
    let maze: Maze
    let theme: Theme

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.bg))
            let cell = min(size.width / CGFloat(maze.width), size.height / CGFloat(maze.height))
            let ox = (size.width - cell * CGFloat(maze.width)) / 2
            let oy = (size.height - cell * CGFloat(maze.height)) / 2
            func px(_ x: Int) -> CGFloat { ox + CGFloat(x) * cell }
            // y flips: maze y-up → canvas y-down
            func py(_ y: Int) -> CGFloat { oy + CGFloat(maze.height - y) * cell }

            var walls = Path()
            for x in 0..<maze.width { for y in 0..<maze.height {
                let c = Coord(x, y)
                if !maze.isOpen(c, .north) { walls.move(to: CGPoint(x: px(x), y: py(y + 1))); walls.addLine(to: CGPoint(x: px(x + 1), y: py(y + 1))) }
                if !maze.isOpen(c, .east)  { walls.move(to: CGPoint(x: px(x + 1), y: py(y)));   walls.addLine(to: CGPoint(x: px(x + 1), y: py(y + 1))) }
                if y == 0, !maze.isOpen(c, .south) { walls.move(to: CGPoint(x: px(x), y: py(0))); walls.addLine(to: CGPoint(x: px(x + 1), y: py(0))) }
                if x == 0, !maze.isOpen(c, .west)  { walls.move(to: CGPoint(x: px(0), y: py(y))); walls.addLine(to: CGPoint(x: px(0), y: py(y + 1))) }
            }}
            ctx.stroke(walls, with: .color(theme.wall), style: StrokeStyle(lineWidth: max(1, cell * 0.16), lineCap: .round))

            let r = cell * 0.3
            func dot(_ c: Coord, _ color: Color) {
                let center = CGPoint(x: px(c.x) + cell / 2, y: py(c.y) - cell / 2)
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(color))
            }
            dot(maze.start, theme.accent)
            dot(maze.goal, Theme.goalRing)
        }
    }
}
