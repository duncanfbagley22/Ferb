import SwiftUI
import SwiftData

private struct UndoEntry: Identifiable {
    enum Kind {
        case logged(Log)
        case setAside
    }
    let id = UUID()
    let kind: Kind
    let targetID: PersistentIdentifier
}

/// End-of-day quick update, opened from the Home focus banner. One card per target that still
/// needs logging: swipe right to log it, swipe left for later (it goes to the back
/// of the stack), or swipe up / tap the moon button for "Not today" (hidden until tomorrow,
/// here and in the alerts). NFC targets are left to Log now.
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
    @State private var dragY: CGFloat = 0
    @State private var isFlinging = false
    @State private var draft = LogDraft()
    @State private var warning: String?

    // MARK: - Which cards

    private var activeTargets: [Target] {
        allTargets.filter { $0.isActive() }
    }

    private func isEligible(_ target: Target) -> Bool {
        !handled.contains(target.persistentModelID) && target.needsQuickUpdate()
    }

    /// Cards still to do: fresh ones first, then skipped ones in the order they were skipped.
    private var queue: [Target] {
        let pending = activeTargets.filter(isEligible)
        let fresh = pending.filter { !skippedOrder.contains($0.persistentModelID) }
        let skipped = skippedOrder.compactMap { id in pending.first { $0.persistentModelID == id } }
        return fresh + skipped
    }

    // MARK: - Set aside ("Not today")

    /// Active targets pushed out of today's stack with "Not today", still waiting for tomorrow.
    private var setAside: [Target] {
        activeTargets.filter { target in
            guard let until = target.snoozedUntil else { return false }
            return until > .now
        }
    }

    private func restore(_ target: Target) {
        target.snoozedUntil = nil
        try? modelContext.save()
        skippedOrder.removeAll { $0 == target.persistentModelID }
    }

    /// The ⋯ menu. Today it restores items set aside with "Not today"; more options can go here.
    private var moreMenu: some View {
        Menu {
            let items = setAside
            if items.isEmpty {
                Button("Nothing set aside today") {}
                    .disabled(true)
            } else {
                Section("Set aside today") {
                    ForEach(items) { target in
                        Button {
                            restore(target)
                        } label: {
                            Label("Restore \(target.item?.name ?? "item")", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More options")
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
                        description: Text("NFC targets aren't shown here. Use Log now on the target.")
                    )
                }
            }
            .navigationTitle("Quick update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    moreMenu
                }
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

            HStack(spacing: 40) {
                Button { commitLeft() } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                            .font(.title2.weight(.semibold))
                            .frame(width: 64, height: 64)
                            .background(Color.blue.opacity(0.2), in: Circle())
                        Text("Later")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Later")

                Button { commitNotToday() } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "moon.zzz")
                            .font(.title2.weight(.semibold))
                            .frame(width: 64, height: 64)
                            .background(Color.gray.opacity(0.25), in: Circle())
                        Text("Not today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Not today")

                Button { commitRight() } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.title2.weight(.semibold))
                            .frame(width: 64, height: 64)
                            .background(Color.green.opacity(0.25), in: Circle())
                        Text("Log")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                Text("Swipe right to log · left for later · up for not today")
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
                .fill(dragY < 0 ? Color.gray : (dragX > 0 ? Color.green : Color.blue))
                .opacity(min(Double(max(abs(dragX), -dragY)) / 250, 0.35))
                .allowsHitTesting(false)
        }
        .offset(x: dragX, y: dragY)
        .rotationEffect(.degrees(Double(dragX) / 25))
        .gesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    guard !isFlinging else { return }
                    if isVerticalDrag(value.translation) {
                        dragX = 0
                        dragY = min(value.translation.height, 0)
                    } else {
                        dragX = value.translation.width
                        dragY = 0
                    }
                }
                .onEnded { value in
                    guard !isFlinging else { return }
                    if isVerticalDrag(value.translation), value.translation.height < -120 {
                        commitNotToday()
                    } else if value.translation.width > 120 {
                        commitRight()
                    } else if value.translation.width < -120 {
                        commitLeft()
                    } else {
                        withAnimation(.spring) {
                            dragX = 0
                            dragY = 0
                        }
                    }
                }
        )
    }

    /// Whichever direction dominates decides: mostly up/down = vertical, otherwise horizontal.
    private func isVerticalDrag(_ translation: CGSize) -> Bool {
        abs(translation.height) > abs(translation.width)
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

    private func commitNotToday() {
        guard let target = queue.first, !isFlinging else { return }
        isFlinging = true
        withAnimation(.easeIn(duration: 0.18)) { dragY = -700 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            let calendar = Calendar.current
            target.snoozedUntil = calendar.date(
                byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)
            )
            try? modelContext.save()
            undoEntry = UndoEntry(kind: .setAside, targetID: target.persistentModelID)
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
        undoEntry = UndoEntry(kind: .logged(entry), targetID: target.persistentModelID)
        resetInputs()
    }

    private func undo(_ entry: UndoEntry) {
        switch entry.kind {
        case .logged(let log):
            if let target = log.target {
                target.remove(log, in: modelContext)
            } else {
                modelContext.delete(log)
                try? modelContext.save()
            }
            handled.remove(entry.targetID)
        case .setAside:
            if let target = allTargets.first(where: { $0.persistentModelID == entry.targetID }) {
                target.snoozedUntil = nil
                try? modelContext.save()
            }
        }
        skippedOrder.removeAll { $0 == entry.targetID }
        undoEntry = nil
        resetInputs()
    }

    private func resetInputs() {
        draft.reset()
        warning = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragX = 0
            dragY = 0
        }
    }

    // MARK: - Undo bar

    @ViewBuilder
    private var undoBar: some View {
        if let entry = undoEntry {
            HStack(spacing: 16) {
                switch entry.kind {
                case .logged: Text("Logged")
                case .setAside: Text("Not today")
                }
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
