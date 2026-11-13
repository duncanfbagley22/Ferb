import SwiftUI
import SwiftData

/// Progress page: summary cards read from the logs (streaks are per target, since there's no
/// whole-day rule yet); the badge grid is still a static, locked placeholder until badge
/// rules are designed.
struct HistoryView: View {
    @Query private var allTargets: [Target]

    private let badgeRows = [3, 2, 3, 2]

    private var cards: [SummaryCard] {
        let targets = allTargets.filter { !$0.isHidden }
        guard !targets.isEmpty else {
            return ["Current streak", "Done this week", "Longest streak"].map {
                SummaryCard(title: $0, value: "—", detail: nil)
            }
        }
        let current = targets.bestCurrentStreak()
        let longest = targets.bestLongestStreak()
        return [
            SummaryCard(
                title: "Current streak",
                value: current?.text ?? "0",
                detail: current?.name
            ),
            SummaryCard(
                title: "Done this week",
                value: "\(targets.doneThisWeek())",
                detail: nil
            ),
            SummaryCard(
                title: "Longest streak",
                value: longest?.text ?? "0",
                detail: longest?.name
            ),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(cards) { card in
                                StatCard(card: card)
                            }
                        }
                    }

                    Text("Badges")
                        .font(.headline)

                    badgeGrid
                }
                .padding()
            }
            .navigationTitle("History")
        }
    }

    /// Staggered diamonds: rows of 3 and 2 alternate so they interlock.
    private var badgeGrid: some View {
        VStack(spacing: -36) {
            ForEach(Array(badgeRows.enumerated()), id: \.offset) { _, count in
                HStack(spacing: 8) {
                    ForEach(0..<count, id: \.self) { _ in
                        BadgeDiamond()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SummaryCard: Identifiable {
    let title: String
    let value: String
    let detail: String?

    var id: String { title }
}

private struct StatCard: View {
    let card: SummaryCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.value)
                .font(.title.bold())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(card.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let detail = card.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 150, height: 90, alignment: .leading)
        .padding(.horizontal)
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct BadgeDiamond: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 52, height: 52)
            .rotationEffect(.degrees(45))
            .frame(width: 80, height: 80)
            .overlay {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
    }
}
