import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedTab: AppTab = .status

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .status:
                    DashboardView()
                case .webGUI:
                    WebGUIView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 24, weight: .semibold))
                            Text(tab.title)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(selectedTab == tab ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 5)
            .padding(.bottom, 6)
            .background(Color(.systemBackground))
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case status
    case webGUI
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "Status"
        case .webGUI: return "Web GUI"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .status: return "dot.radiowaves.left.and.right"
        case .webGUI: return "safari"
        case .settings: return "gearshape"
        }
    }
}
