import SwiftUI

/// The rules — shown automatically on first launch and always reachable from the "?" on the
/// game screen (ship-with-onboarding, build 1).
struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("How to play").font(Typeface.h1).foregroundStyle(Theme.onInk)
                    Spacer()
                    Button("Done") { dismiss() }.font(Typeface.body).foregroundStyle(Theme.checkpoint)
                }
                section("Trace, don't lift", "Press your finger on the glowing start dot and drag through the corridors to the goal — all in one continuous motion. Lift early and the trace resets to the start.")
                section("Walls stop you", "You can only move along open corridors. Push into a wall and you'll feel a buzz; the trail just won't go there. Find another way.")
                section("Backtrack to re-route", "Hit a dead end? Slide your finger back the way you came and the trail rewinds, cell by cell, to the last junction. Then take a different branch.")
                section("Checkpoints", "Touching a checkpoint (mint ring) saves your spot. If a trap throws you back, you return here instead of all the way to start.")
                section("Spikes", "Spiked tiles (red stars) snap you back to your last checkpoint. There's always a spike-free route — you just have to find it.")
                section("Timed gates", "A gate is a wall that opens and closes on a rhythm. Cyan = open, red = shut. Time your approach and slip through while it's open.")
                section("One-way corridors", "An arrow means you can only go that direction — and you can't backtrack through it. Commit carefully.")
                section("Moving hazards & phantoms", "Orange orbs patrol the maze; ghostly tiles blink in and out. Both reset you if you touch them at the wrong moment. Watch the rhythm.")
                section("Race the clock", "Your time and backtrack count are scored. Beat par with zero backtracks for all three stars — and climb the online leaderboards.")
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.ink.ignoresSafeArea())
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Typeface.h2).foregroundStyle(Theme.onInk)
            Text(body).font(Typeface.body).foregroundStyle(Theme.onInkDim)
        }
    }
}
