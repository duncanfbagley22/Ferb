import SwiftUI
import SwiftData

private struct UndoEntry: Identifiable {
    let id = UUID()
    let log: Log
    let targetID: PersistentIdentifier
}

/// End-of-day quick update, opened from the Home focus banner. One card per target that still
/// needs logging: swipe right to log it, swipe left to skip it for now (it goes to the back
/// of the stack). Caps and NFC targets are left to Log now.
struct QuickInputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Target.startDate) private var allTargets: [Target]

    /// Logged during this visit, so a partly-met target doesn't come straight back.
    @State private var handled: Set<PersistentIdentifier> = []
    /// Skipped targets, in the order they were skipped; they sit behind everything else.
    @State private var skippedOrder: [PersistentIdentifier] = []
    @State private var undoEntry: UndoEntry?

    @State private var dragX: CGFloat = 0
    @State private var isFlinging = false
    @State private var draft = LogDraft()
    @State private var warning: String?

    // MARK: - Which cards

    private var activeTargets: [Target] {
        allTargets.filter { $0.isActive() }
    }

    private func isEligible(_ target: Target) -> Bool {
        !handled.contains(target.persistentModelID) && target.needsQuickLog()
    }

    /// Cards still to do: fresh ones first, then skipped ones in the order they were skipped.
    private var queue: [Target] {
        let pending = activeTargets.filter(isEligible)
        let fresh = pending.filter { !skippedOrder.contains($0.persistentModelID) }
        let skipped = skippedOrder.compactMap { id in pending.first { $0.persistentModelID == id } }
        return fresh + skipped
    }

    // MARK: - Body

    var body: some View {
        let cards = queue
        return NavigationStack {
            Group {
                if let top = cards.first {
                    stack(top: top, next: cards.dropFirst().first, count: cards.count)
                } else if activeTargets.isEmpty {
                    ContentUnavailableView(
                        "No active targets",
                        systemImage: "scope",
                        description: Text("Targets you're working on will show up here.")
                    )
                } else {
                    ContentUnavailableView(
                        "You're all caught up",
                        systemImage: "checkmark.circle",
                        description: Text("Caps and NFC targets aren't shown here. Use Log now on the target.")
                    )
                }
            }
            .navigationTitle("Quick update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) { undoBar }
            .animation(.default, value: undoEntry?.id)
            .onChange(of: draft.numberText) { warning = nil }
        }
    }

    private func stack(top: Target, next: Target?, count: Int) -> some View {
        VStack(spacing: 20) {
            Text("\(count) left")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ZStack {
                if let next { backCard(next) }
                card(for: top)
                    .id(top.persistentModelID)
            }
            .padding(.horizontal)

            HStack(spacing: 48) {
                Button { commitLeft() } label: {
                    Image(systemName: "xmark")
                        .font(.title2.weight(.semibold))
                        .frame(width: 64, height: 64)
                        .background(Color.orange.opacity(0.2), in: Circle())
                }
                .accessibilityLabel("Skip for now")

                Button { commitRight() } label: {
                    Image(systemName: "checkmark")
                        .font(.title2.weight(.semibold))
                        .frame(width: 64, height: 64)
                        .background(Color.green.opacity(0.25), in: Circle())
                }
                .accessibilityLabel("Log it")
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.top)
    }

    // MARK: - Cards

    private func backCard(_ target: Target) -> some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(.tertiarySystemBackground))
            .frame(maxWidth: .infinity, minHeight: 340)
            .overlay(alignment: .topLeading) {
                Text(target.item?.name ?? "Item")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
                    .padding(20)
            }
            .scaleEffect(0.94)
            .offset(y: 14)
    }

    private func card(for target: Target) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(target.item?.name ?? "Item")
                    .font(.title2.bold())
                Text(subtitle(for: target))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let soFar = target.loggedSoFarText {
                    Text(soFar)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
            TargetLogInputs(target: target, draft: draft)
            Spacer(minLength: 0)

            if let warning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Swipe right to log · left to skip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color(.secondarySystemBackground)))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .fill(dragX > 0 ? Color.green : Color.orange)
                .opacity(min(Double(abs(dragX)) / 250, 0.35))
                .allowsHitTesting(false)
        }
        .offset(x: dragX)
        .rotationEffect(.degrees(Double(dragX) / 25))
        .gesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    guard !isFlinging else { return }
                    dragX = value.translation.width
                }
                .onEnded { value in
                    guard !isFlinging else { return }
                    if value.translation.width > 120 {
                        commitRight()
                    } else if value.translation.width < -120 {
                        commitLeft()
                    } else {
                        withAnimation(.spring) { dragX = 0 }
                    }
                }
        )
    }

    private func subtitle(for target: Target) -> String {
        [target.cadenceTitle, target.valueSummary].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Swiping

    private func commitRight() {
        guard let target = queue.first, !isFlinging else { return }
        switch draft.resolve(target) {
        case .invalid(let message):
            warning = message
            withAnimation(.spring) { dragX = 0 }
        case .value(let value):
            isFlinging = true
            withAnimation(.easeIn(duration: 0.18)) { dragX = 600 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                log(target, value: value)
                isFlinging = false
            }
        }
    }

    private func commitLeft() {
        guard let target = queue.first, !isFlinging else { return }
        isFlinging = true
        withAnimation(.easeIn(duration: 0.18)) { dragX = -600 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            let id = target.persistentModelID
            skippedOrder.removeAll { $0 == id }
            skippedOrder.append(id)
            resetInputs()
            isFlinging = false
        }
    }

    private func log(_ target: Target, value: Double?) {
        let entry = target.record(value: value, in: modelContext)
        if target.logInputKind == .durationTimer {
            target.clearTimer()
        }
        try? modelContext.save()
        handled.insert(target.persistentModelID)
        undoEntry = UndoEntry(log: entry, targetID: target.persistentModelID)
        resetInputs()
    }

    private func undo(_ entry: UndoEntry) {
        if let target = entry.log.target {
            target.remove(entry.log, in: modelContext)
        } else {
            modelContext.delete(entry.log)
            try? modelContext.save()
        }
        handled.remove(entry.targetID)
        skippedOrder.removeAll { $0 == entry.targetID }
        undoEntry = nil
        resetInputs()
    }

    private func resetInputs() {
        draft.reset()
        warning = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { dragX = 0 }
    }

    // MARK: - Undo bar

    @ViewBuilder
    private var undoBar: some View {
        if let entry = undoEntry {
            HStack(spacing: 16) {
                Text("Logged")
                Button("Undo") { undo(entry) }
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: entry.id) {
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled, undoEntry?.id == entry.id {
                    undoEntry = nil
                }
            }
        }
    }
}
