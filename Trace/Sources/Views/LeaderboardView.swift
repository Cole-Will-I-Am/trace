import SwiftUI

/// Online boards (§4): per-level best time and fewest backtracks, plus a total-time board
/// across all 21. Anonymous by default; Sign in with Apple to claim a name across devices.
struct LeaderboardView: View {
    @ObservedObject var account: Account
    @ObservedObject var progress: Progress
    @Environment(\.dismiss) private var dismiss

    enum Scope: Hashable { case total; case level(Int) }
    @State private var scope: Scope = .total
    @State private var metric = "time"
    @State private var board: BoardResponse?
    @State private var loading = false
    @State private var showName = false
    @State private var nameDraft = ""

    var body: some View {
        NavigationStack {
            List {
                Section { scopePicker } header: { Text("Board").foregroundStyle(Theme.onInkDim) }

                Section {
                    if loading { HStack { Spacer(); ProgressView().tint(Theme.onInk); Spacer() } }
                    else if let board, !board.entries.isEmpty {
                        ForEach(Array(board.entries.enumerated()), id: \.element.id) { i, e in
                            row(rank: i + 1, name: e.name, value: format(e.value), extra: e.extra)
                        }
                    } else {
                        Text("No scores yet — be the first.").foregroundStyle(Theme.onInkDim)
                    }
                } header: {
                    Text(scope == .total ? "Total completion time" :
                            (metric == "time" ? "Best time" : "Fewest backtracks"))
                        .foregroundStyle(Theme.onInkDim)
                } footer: {
                    if let me = board?.me {
                        Text("You: #\(me.rank) · \(format(me.value)) · top \(String(format: "%.0f", 100 - me.percentile))%")
                            .foregroundStyle(Theme.checkpoint)
                    }
                }

                accountSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink.ignoresSafeArea())
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task(id: scopeKey) { await reload() }
        }
    }

    private var scopeKey: String {
        switch scope { case .total: return "total"; case .level(let l): return "l\(l)-\(metric)" }
    }

    private var scopePicker: some View {
        VStack(spacing: 10) {
            Picker("Scope", selection: Binding(
                get: { if case .level = scope { return 1 } else { return 0 } },
                set: { scope = $0 == 0 ? .total : .level(currentLevel) })) {
                Text("Total").tag(0); Text("By level").tag(1)
            }.pickerStyle(.segmented)

            if case .level = scope {
                HStack {
                    Picker("Level", selection: Binding(
                        get: { currentLevel },
                        set: { scope = .level($0) })) {
                        ForEach(Levels.all, id: \.id) { Text("\($0.id). \($0.title)").tag($0.id) }
                    }.tint(Theme.onInk)
                    Spacer()
                    Picker("Metric", selection: $metric) {
                        Text("Time").tag("time"); Text("Backtracks").tag("backtracks")
                    }.pickerStyle(.segmented).frame(width: 170)
                }
            }
        }
    }

    private var currentLevel: Int { if case .level(let l) = scope { return l } else { return 1 } }

    private func row(rank: Int, name: String, value: String, extra: Int?) -> some View {
        HStack {
            Text("\(rank)").font(Typeface.mono(14, .semibold)).foregroundStyle(Theme.onInkDim).frame(width: 30, alignment: .leading)
            Text(name).foregroundStyle(Theme.onInk).lineLimit(1)
            if let extra { Text("· \(extra)/\(Levels.count)").font(Typeface.cap).foregroundStyle(Theme.onInkDim) }
            Spacer()
            Text(value).font(Typeface.mono(14, .semibold)).foregroundStyle(Theme.onInk)
        }
        .listRowBackground(Theme.inkRaised)
    }

    @ViewBuilder private var accountSection: some View {
        Section {
            if account.isSignedIn {
                HStack { Text("Signed in").foregroundStyle(Theme.onInk); Spacer()
                    Text(account.displayName).foregroundStyle(Theme.onInkDim) }
                Button("Change username") { nameDraft = account.player?.username ?? ""; showName = true }
                Button("Delete account & scores", role: .destructive) { Task { await account.deleteAccount() } }
            } else {
                Button { account.startSignIn() } label: {
                    Label("Sign in with Apple", systemImage: "applelogo").foregroundStyle(Theme.onInk)
                }
                Button("Set a username") { nameDraft = ""; showName = true }
            }
        } header: { Text("Account").foregroundStyle(Theme.onInkDim) }
        .listRowBackground(Theme.inkRaised)
        .alert("Username", isPresented: $showName) {
            TextField("3–16 letters/numbers", text: $nameDraft)
            Button("Save") { let n = nameDraft; Task { _ = await account.setUsername(n) } }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func reload() async {
        loading = true; board = nil
        switch scope {
        case .total: board = await account.totalBoard()
        case .level(let l): board = await account.board(level: l, metric: metric)
        }
        loading = false
    }

    private func format(_ v: Int) -> String {
        if scope == .total || metric == "time" { return v.asClock }
        return "\(v)"
    }
}
