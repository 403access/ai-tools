import SwiftUI

struct RecentSessionRow: View {
    let session: Session
    let project: String

    var body: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text(project)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                    if let model = session.model {
                        Chip(text: model.id)
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.relative(from: session.time.updatedDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if session.cost > 0 {
                    Text(Fmt.usd(session.cost))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
                Text(Fmt.compact(session.tokens.generated) + " tok")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 12)
    }
}
