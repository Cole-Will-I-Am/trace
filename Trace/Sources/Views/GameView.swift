import SwiftUI
import SpriteKit

struct GameView: View {
    @StateObject private var vm: GameViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHowTo = false

    private let onExit: () -> Void
    private let onNext: (() -> Void)?

    init(levelID: Int, progress: Progress, account: Account,
         onExit: @escaping () -> Void, onNext: (() -> Void)?) {
        _vm = StateObject(wrappedValue: GameViewModel(levelID: levelID, progress: progress, account: account))
        self.onExit = onExit
        self.onNext = onNext
    }

    private var theme: Theme { vm.theme }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 10) {
                topBar
                Spacer(minLength: 0)
                SpriteView(scene: vm.scene, options: [.ignoresSiblingOrder])
                    .aspectRatio(CGFloat(vm.spec.width) / CGFloat(vm.spec.height), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1))
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if !vm.started && !vm.won { startPrompt }
            if vm.won { winOverlay }
        }
        .navigationBarHidden(true)
        .onAppear { vm.setReduceMotion(reduceMotion) }
        .onChange(of: reduceMotion) { _, v in vm.setReduceMotion(v) }
        .sheet(isPresented: $showHowTo) { HowToPlayView() }
    }

    private var topBar: some View {
        HStack {
            Button(action: onExit) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.onInkDim).padding(8)
            }
            Spacer()
            VStack(spacing: 1) {
                Text("Level \(vm.levelID)").font(Typeface.cap).foregroundStyle(Theme.onInkDim)
                Text(vm.spec.title).font(Typeface.h2).foregroundStyle(theme.accentHi)
            }
            Spacer()
            Button { showHowTo = true } label: {
                Image(systemName: "questionmark.circle").font(.system(size: 20))
                    .foregroundStyle(Theme.onInkDim).padding(8)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            stat(label: "time", value: vm.elapsedMs.asClock, tint: vm.elapsedMs <= vm.parMs ? theme.accentHi : Theme.onInk)
            Spacer()
            stat(label: "par", value: vm.parMs.asClock, tint: Theme.onInkDim)
            Spacer()
            stat(label: "backtracks", value: "\(vm.backtracks)", tint: Theme.onInk)
            Spacer()
            Button { vm.retry() } label: {
                Label("Retry", systemImage: "arrow.counterclockwise")
                    .font(Typeface.cap).foregroundStyle(Theme.onInk)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(Theme.inkRaised))
            }
        }
        .padding(.horizontal, 4)
    }

    private func stat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(Typeface.cap).foregroundStyle(Theme.onInkDim)
            Text(value).font(Typeface.mono(20, .bold)).monospacedDigit().foregroundStyle(tint)
        }
    }

    private var startPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.point.up.left.fill").font(.system(size: 30)).foregroundStyle(theme.accent)
            Text("Press the glowing start dot,\nthen trace to the goal without lifting.")
                .multilineTextAlignment(.center).font(Typeface.body).foregroundStyle(Theme.onInk)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.ink.opacity(0.82)))
        .padding(.bottom, 120)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var winOverlay: some View {
        ZStack {
            theme.bg.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Solved").font(Typeface.h1).foregroundStyle(theme.accentHi)
                if let r = vm.result { stars(r.stars) }
                VStack(spacing: 2) {
                    Text(vm.elapsedMs.asClock).font(Typeface.mono(46, .bold)).monospacedDigit()
                        .foregroundStyle(Theme.onInk)
                    Text(vm.result?.beatPar == true ? "under par · \(vm.parMs.asClock)" : "par \(vm.parMs.asClock)")
                        .font(Typeface.cap).foregroundStyle(vm.result?.beatPar == true ? theme.accent : Theme.onInkDim)
                }
                HStack(spacing: 22) {
                    miniStat("backtracks", "\(vm.backtracks)")
                    if vm.result?.isNewBest == true { miniStat("result", "new best ✦") }
                    if let rank = vm.onlineRank { miniStat("rank", rank) }
                }
                buttons
            }
            .padding(30)
        }
        .transition(.opacity)
    }

    private func stars(_ n: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < n ? "star.fill" : "star")
                    .font(.system(size: 22)).foregroundStyle(i < n ? Theme.goalRing : Theme.onInkDim)
            }
        }
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(Typeface.mono(15, .semibold)).foregroundStyle(Theme.onInk)
            Text(label).font(Typeface.cap).foregroundStyle(Theme.onInkDim)
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if let onNext {
                Button { onNext() } label: {
                    Text("Next level").font(Typeface.display(18, .bold)).foregroundStyle(theme.bg)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 14).fill(theme.accent))
                }
            }
            HStack(spacing: 10) {
                Button { vm.retry() } label: {
                    Text("Replay").font(Typeface.display(16, .semibold)).foregroundStyle(Theme.onInk)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.inkRaised))
                }
                Button(action: onExit) {
                    Text("Levels").font(Typeface.display(16, .semibold)).foregroundStyle(Theme.onInk)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.inkRaised))
                }
            }
        }
        .padding(.top, 6).padding(.horizontal, 8)
    }
}
