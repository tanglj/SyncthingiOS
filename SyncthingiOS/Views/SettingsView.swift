import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: SyncthingStore
    @EnvironmentObject private var core: SyncthingCoreManager
    @State private var isRestartConfirmationPresented = false
    @State private var draftBaseURL = ""
    @State private var draftAPIKey = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    connectionStatus
                    embeddedCoreCard
                    syncFolderCard
                    connectionForm
                    syncthingActions
                    aboutCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                draftBaseURL = settings.baseURLString
                draftAPIKey = settings.apiKey
            }
            .confirmationDialog(
                "Restart Syncthing?",
                isPresented: $isRestartConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Restart", role: .destructive) {
                    Task { await store.restart() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                Image(systemName: statusIcon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text(statusTitle)
                    .font(.title3.weight(.bold))
                Text(statusSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var connectionForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connection")
                .font(.title3.weight(.bold))

            inputBlock(
                title: "GUI address",
                systemImage: "network",
                placeholder: "http://172.20.10.2:8384",
                text: $draftBaseURL,
                isSecure: false
            )

            inputBlock(
                title: "API key",
                systemImage: "key.fill",
                placeholder: "Syncthing API key",
                text: $draftAPIKey,
                isSecure: true
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Target URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(normalizedDraftBaseURLString)
                    .font(.callout.monospaced())
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                saveAndConnect()
            } label: {
                Label("Save & Connect", systemImage: "bolt.horizontal.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSave)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var embeddedCoreCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Embedded Core")
                .font(.title3.weight(.bold))

            HStack(spacing: 13) {
                Image(systemName: coreStatusIcon)
                    .font(.headline)
                    .foregroundStyle(coreStatusColor)
                    .frame(width: 34, height: 34)
                    .background(coreStatusColor.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(core.state.title)
                        .font(.headline)
                    Text(core.state.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await core.start()
                        if core.state.isRunning {
                            settings.useEmbeddedCore()
                            draftBaseURL = settings.baseURLString
                            draftAPIKey = settings.apiKey
                            store.configure(with: settings.snapshot)
                            await store.refresh()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if core.state.isStarting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(core.state.isStarting ? "Starting" : "Start")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!core.state.canStart)

                Button {
                    Task { await core.stop() }
                } label: {
                    HStack(spacing: 8) {
                        if core.state.isStopping {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "stop.fill")
                        }
                        Text(core.state.isStopping ? "Stopping" : "Stop")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
                .buttonStyle(.bordered)
                .disabled((!core.state.isRunning && !core.state.isStarting) || core.state.isStopping)
            }

            Button {
                settings.useEmbeddedCore()
                draftBaseURL = settings.baseURLString
                draftAPIKey = settings.apiKey
                store.configure(with: settings.snapshot)
                Task { await store.refresh() }
            } label: {
                Label("Use Local Core API", systemImage: "link")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var syncFolderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sync Folder")
                .font(.title3.weight(.bold))

            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)
                    .frame(width: 34, height: 34)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("App Documents / Syncthing")
                        .font(.headline)
                    Text("Syncthing writes only inside this app's own Documents directory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var syncthingActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Syncthing")
                .font(.title3.weight(.bold))

            Button(role: .destructive) {
                isRestartConfirmationPresented = true
            } label: {
                Label("Restart Syncthing", systemImage: "power")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!store.isConfigured)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var aboutCard: some View {
        VStack(spacing: 12) {
            infoRow("Client", value: "SwiftUI foreground core")
            Divider()
            infoRow("Version", value: "0.1.0")
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func inputBlock(
        title: String,
        systemImage: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(.URL)
                }
            }
            .font(.body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(14)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }

    private var canSave: Bool {
        URL(string: normalizedDraftBaseURLString)?.host != nil &&
        !draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var normalizedDraftBaseURLString: String {
        let trimmed = draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "http://\(trimmed)"
    }

    private func saveAndConnect() {
        settings.update(baseURLString: draftBaseURL, apiKey: draftAPIKey)
        store.configure(with: settings.snapshot)
        Task { await store.refresh() }
    }

    private var statusTitle: String {
        if store.isLoading { return "Connecting" }
        if store.errorMessage != nil { return "Connection issue" }
        if store.lastConnectedAt != nil { return "Connected" }
        return "Not connected"
    }

    private var statusSubtitle: String {
        if store.isLoading { return "Checking the Syncthing REST API." }
        if let errorMessage = store.errorMessage { return errorMessage }
        if let lastConnectedAt = store.lastConnectedAt {
            return "Last connected \(lastConnectedAt.formatted(date: .omitted, time: .shortened))"
        }
        return "Enter the GUI address and API key."
    }

    private var statusIcon: String {
        if store.isLoading { return "arrow.triangle.2.circlepath" }
        if store.errorMessage != nil { return "exclamationmark.triangle.fill" }
        if store.lastConnectedAt != nil { return "checkmark.seal.fill" }
        return "link.badge.plus"
    }

    private var statusColor: Color {
        if store.errorMessage != nil { return .orange }
        if store.lastConnectedAt != nil { return .green }
        return .blue
    }

    private var coreStatusIcon: String {
        switch core.state {
        case .running:
            return "checkmark.circle.fill"
        case .starting:
            return "hourglass"
        case .stopping:
            return "stop.circle.fill"
        case .stopped:
            return "power.circle"
        case .unavailable:
            return "shippingbox"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var coreStatusColor: Color {
        switch core.state {
        case .running:
            return .green
        case .starting:
            return .blue
        case .stopping:
            return .orange
        case .stopped, .unavailable:
            return .secondary
        case .failed:
            return .orange
        }
    }
}
