import SwiftUI

/// One item in an area's list: name, subarea, how it's measured, and how many targets it has.
struct ItemRow: View {
    let item: Item

    var body: some View {
        HStack {
            NavigationLink(value: item) {
                VStack(alignment: .leading) {
                    Text(item.name)
                    Text("\(item.subarea?.title ?? "No subarea") · \(item.typeSummary) · \(item.targets.count) target\(item.targets.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                item.isPriority.toggle()
            } label: {
                Image(systemName: item.isPriority ? "star.fill" : "star")
                    .foregroundStyle(item.isPriority ? Color(red: 0.75, green: 0.58, blue: 0.0) : .secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Compact card for an item with no active target, sized to sit in the same 3-across grid as
/// `TargetGridCard`. Tap opens the item page. Gray with a dashed outline, since there's no
/// status to tint it with.
struct ItemGridCard: View {
    let item: Item

    private var targetCountText: String {
        let count = item.targets.count
        return count == 0 ? "No targets yet" : "\(count) target\(count == 1 ? "" : "s")"
    }

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Text(targetCountText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

extension Item {
    /// Short description of how the item is measured, e.g. "Did it" or "Amount · steps · Target".
    var typeSummary: String {
        switch trackingType {
        case .binary:
            return binarySubtype?.title ?? "Binary"
        case .quantity:
            var parts = [quantitySubtype?.title ?? "Quantity"]
            if !unitName.isEmpty { parts.append(unitName) }
            if let quantityDirection { parts.append(quantityDirection.title) }
            return parts.joined(separator: " · ")
        }
    }
}
