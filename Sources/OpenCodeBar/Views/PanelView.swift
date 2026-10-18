import SwiftUI

struct PanelView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider().opacity(0.5)

            TabBar(selection: $state.tab)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch state.tab {
                    case .live:
                        LiveTab()
                    case .usage:
                        UsageTab()
                    }
                }
                .padding(12)
            }
            .frame(height: 500)

            Divider().opacity(0.5)
            FooterView()
        }
        .frame(width: 400)
        .task {
            await state.refreshLive()
            await state.refreshStats()
        }
    }
}

struct TabBar: View {
    @Binding var selection: AppState.Tab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppState.Tab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon).font(.system(size: 11, weight: .semibold))
                        Text(tab.rawValue).font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selection == tab ? Color.primary.opacity(0.12) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

struct FooterView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.activeCount > 0 ? Theme.running : Color.secondary.opacity(0.5))
                .frame(width: 5, height: 5)
            Text("\(state.activeCount) active")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            if let updated = state.lastUpdated {
                Text("Updated \(Fmt.relative(from: updated))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
