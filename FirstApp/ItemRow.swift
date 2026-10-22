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

extension Item {
    /// Short description of how the item is measured, e.g. "Did it" or "Amount · steps · Target".
    var typeSummary: String {
        switch trackingType {
        case .binary:
            return binarySubtype?.title ?? "Binary"
        case .quantity:
            var parts = [quantitySubtype?.title ?? "Quantity"]
            if let unit { parts.append(unit.title.lowercased()) }
            if let quantityDirection { parts.append(quantityDirection.title) }
            return parts.joined(separator: " · ")
        }
    }
}
