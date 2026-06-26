import SwiftUI

/// App root: owns local progress + the leaderboard account, routes level-select → game →
/// next level, and shows the rules on first launch.
struct RootView: View {
    @StateObject private var progress = Progress()
    @StateObject private var account = Account()
    @State private var path: [Int] = []
    @State private var showHowTo = false

    var body: some View {
        NavigationStack(path: $path) {
            LevelSelectView(progress: progress, account: account, onPlay: { path.append($0) })
                .navigationDestination(for: Int.self) { id in
                    GameView(levelID: id, progress: progress, account: account,
                             onExit: { path = [] },
                             onNext: id < Levels.count ? { path = [id + 1] } : nil)
                }
        }
        .tint(Theme.onInk)
        .task { await account.bootstrap() }
        .onAppear { if !progress.seenHowTo { showHowTo = true; progress.markSeenHowTo() } }
        .sheet(isPresented: $showHowTo) { HowToPlayView() }
    }
}
