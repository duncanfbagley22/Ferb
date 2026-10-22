import SwiftUI
import SwiftData

/// End-of-day quick update, opened from the Home focus banner. Placeholder-grade: check items
/// can be marked done right here, everything else points to the Record tab.
struct QuickInputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Target.startDate) private var allTargets: [Target]

    private var targets: [Target] {
        allTargets.filter { $0.isActive() }
    }

    var body: some View {
        NavigationStack {
            Group {
                if targets.isEmpty {
                    ContentUnavailableView(
                        "No active targets",
                        systemImage: "scope",
                        description: Text("Targets you're working on will show up here.")
                    )
                } else {
                    List(targets) { target in
                        row(for: target)
                    }
                }
            }
            .navigationTitle("Quick update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Whether the target's current period is already met, so a weekly target done on
    /// Monday stays checked all week.
    private func isDone(_ target: Target) -> Bool {
        target.recentPeriods(1).first(where: \.isCurrent)?.result == .done
    }

    @ViewBuilder
    private func row(for target: Target) -> some View {
        let done = isDone(target)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.item?.name ?? "Item")
                Text(target.cadenceTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if target.item?.effectiveMethod == .check {
                Button {
                    modelContext.insert(Log(target: target))
                    try? modelContext.save()
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(done)
            } else {
                Text("Use Record tab")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
