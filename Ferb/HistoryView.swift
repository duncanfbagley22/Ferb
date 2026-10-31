import SwiftUI

/// Placeholder progress page: summary cards and a badge grid. Everything here is static
/// until streaks and badge rules are designed.
struct HistoryView: View {
    private let cards = ["Current streak", "Done this week", "Longest streak"]
    private let badgeRows = [3, 2, 3, 2]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(cards, id: \.self) { title in
                                StatCard(title: title)
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

private struct StatCard: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("—")
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
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
