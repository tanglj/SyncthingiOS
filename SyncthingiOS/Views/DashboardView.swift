import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: SyncthingStore
    @EnvironmentObject private var core: SyncthingCoreManager

    private var folders: [Folder] {
        (store.overview.config?.folders ?? [])
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    private var devices: [Device] {
        (store.overview.config?.devices ?? [])
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    private var onlineDeviceCount: Int? {
        guard let connections = store.overview.connections?.connections else { return nil }
        return connections.values.filter { $0.connected == true }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    coreStatusCard

                    if let errorMessage = store.errorMessage {
                        errorBanner(errorMessage)
                    }

                    metricsGrid

                    sectionHeader("Folders", count: folders.count)
                    if folders.isEmpty {
                        placeholderCard("No folders", systemImage: "folder.badge.questionmark")
                    } else {
                        VStack(spacing: 12) {
                            ForEach(folders) { folder in
                                folderCard(folder)
                            }
                        }
                    }

                    sectionHeader("Devices", count: devices.count)
                    if devices.isEmpty {
                        placeholderCard("No devices", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                    } else {
                        VStack(spacing: 12) {
                            ForEach(devices) { device in
                                deviceCard(device)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 26)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Syncthing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await store.rescan() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!store.overview.hasData)

                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                await store.refresh()
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(connectionColor.opacity(0.14))
                    Image(systemName: connectionIcon)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(connectionColor)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 7) {
                    Text(connectionTitle)
                        .font(.title3.weight(.bold))
                    Text(connectionSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let myID = store.overview.status?.myID, !myID.isEmpty {
                Label {
                    Text(myID)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "number")
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var metricsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                metricCard(
                    "Folders",
                    value: store.overview.config?.folders.count,
                    systemImage: "folder",
                    color: .blue
                )
                metricCard(
                    "Devices",
                    value: store.overview.config?.devices.count,
                    systemImage: "desktopcomputer",
                    color: .indigo
                )
            }
            HStack(spacing: 10) {
                metricCard(
                    "Online",
                    value: onlineDeviceCount,
                    systemImage: "wifi",
                    color: .green
                )
                metricCard(
                    "Uptime",
                    valueText: store.overview.status?.uptime?.durationText ?? "-",
                    systemImage: "clock",
                    color: .orange
                )
            }
        }
    }

    private var coreStatusCard: some View {
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
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 2)
    }

    private func metricCard(
        _ title: String,
        value: Int?,
        systemImage: String,
        color: Color
    ) -> some View {
        metricCard(title, valueText: value.map(String.init) ?? "-", systemImage: systemImage, color: color)
    }

    private func metricCard(
        _ title: String,
        valueText: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(valueText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func folderCard(_ folder: Folder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: folder.paused == true ? "pause.circle.fill" : "folder.fill")
                    .font(.title2)
                    .foregroundStyle(folder.paused == true ? .orange : .blue)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(folder.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(folder.type ?? "folder")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await store.rescan(folderID: folder.id) }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rescan \(folder.displayName)")
            }

            if let path = folder.path, !path.isEmpty {
                Text(path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text("\(folder.sharedDeviceCount) shared devices")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func deviceCard(_ device: Device) -> some View {
        let connection = store.overview.connections?.connections[device.deviceID]
        let isConnected = connection?.connected == true

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: device.paused == true ? "pause.circle.fill" : "desktopcomputer")
                    .font(.title2)
                    .foregroundStyle(device.paused == true ? .orange : (isConnected ? .green : .secondary))
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(connection?.stateText ?? "Unknown")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isConnected ? .green : .secondary)
                }

                Spacer()
            }

            Text(device.deviceID)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let address = connection?.address, !address.isEmpty {
                Label(address, systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func placeholderCard(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func errorBanner(_ message: String) -> some View {
        Label {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.orange)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var connectionTitle: String {
        if store.isLoading { return "Connecting" }
        if store.errorMessage != nil { return "Connection issue" }
        if let version = store.overview.version?.version { return version }
        return store.isConfigured ? "Ready to connect" : "Set up connection"
    }

    private var connectionSubtitle: String {
        if store.isLoading { return "Fetching status from Syncthing." }
        if store.errorMessage != nil { return "Check the address, API key, and network access." }
        if let lastConnectedAt = store.lastConnectedAt {
            return "Last updated \(lastConnectedAt.formatted(date: .omitted, time: .shortened))"
        }
        return store.isConfigured ? "Pull down or tap Refresh to load status." : "Add the GUI address and API key in Settings."
    }

    private var connectionIcon: String {
        if store.isLoading { return "arrow.triangle.2.circlepath" }
        if store.errorMessage != nil { return "exclamationmark.triangle.fill" }
        if store.overview.hasData { return "checkmark.seal.fill" }
        return "link"
    }

    private var connectionColor: Color {
        if store.errorMessage != nil { return .orange }
        if store.overview.hasData { return .green }
        return .blue
    }

    private var coreStatusIcon: String {
        switch core.state {
        case .running:
            return "checkmark.circle.fill"
        case .starting:
            return "hourglass"
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
        case .stopped, .unavailable:
            return .secondary
        case .failed:
            return .orange
        }
    }
}
