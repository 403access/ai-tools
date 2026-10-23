import SwiftUI

struct RecentRow: View {
    let session: Session
    let project: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(project)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                    if let model = session.model {
                        Chip(text: model.id)
                    }
                    Text(Fmt.relative(from: session.time.updatedDate))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                if session.cost > 0 {
                    Text(Fmt.usd(session.cost))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("free")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(Fmt.compact(session.tokens.generated) + " tok")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 10)
    }
}
