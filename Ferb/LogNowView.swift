import SwiftUI
import SwiftData

/// Log one target right now, whatever its state: a cap, a target that's already met, or one
/// that's only logged by NFC. Uses the same inputs as Quick update.
struct LogNowView: View {
    let target: Target

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var draft = LogDraft()
    @State private var warning: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.item?.name ?? "Item")
                        .font(.title2.bold())
                    Text([target.cadenceTitle, target.valueSummary].compactMap { $0 }.joined(separator: " · "))
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
                }

                Button { save() } label: {
                    Text("Log").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("Log now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: draft.numberText) { warning = nil }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        switch draft.resolve(target) {
        case .invalid(let message):
            warning = message
        case .value(let value):
            target.record(value: value, in: modelContext)
            if target.logInputKind == .durationTimer {
                target.clearTimer()
            }
            try? modelContext.save()
            dismiss()
        }
    }
}
