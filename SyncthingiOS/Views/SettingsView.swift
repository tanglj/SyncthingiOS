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
                    appStoreReadinessCard
                    openSourceCard
                    aboutCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                draftBaseURL = settings.baseURLString
                draftAPIKey = settings.apiKey
            }
            .confirmationDialog(
                "重启 Syncthing？",
                isPresented: $isRestartConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("重启", role: .destructive) {
                    Task { await store.restart() }
                }
                Button("取消", role: .cancel) {}
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
            Text("连接")
                .font(.title3.weight(.bold))

            inputBlock(
                title: "GUI 地址",
                systemImage: "network",
                placeholder: "http://172.20.10.2:8384",
                text: $draftBaseURL,
                isSecure: false
            )

            inputBlock(
                title: "API Key",
                systemImage: "key.fill",
                placeholder: "Syncthing API Key",
                text: $draftAPIKey,
                isSecure: true
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("目标 URL")
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
                Label("保存并连接", systemImage: "bolt.horizontal.circle.fill")
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
            Text("内置核心")
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
                        Text(core.state.isStarting ? "启动中" : "启动")
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
                        Text(core.state.isStopping ? "停止中" : "停止")
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
                Label("使用本机核心 API", systemImage: "link")
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
            Text("同步文件夹")
                .font(.title3.weight(.bold))

            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)
                    .frame(width: 34, height: 34)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("我的iPhone / Syncthing")
                        .font(.headline)
                    Text("Syncthing 只会写入本应用自己的 Documents 目录。")
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
                Label("重启 Syncthing", systemImage: "power")
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

    private var appStoreReadinessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("上架说明")
                .font(.title3.weight(.bold))

            complianceRow(
                systemImage: "info.circle.fill",
                title: "非官方客户端",
                message: "本应用不是 Syncthing 官方产品，Syncthing 名称归其项目所有。"
            )
            complianceRow(
                systemImage: "iphone.and.arrow.forward",
                title: "前台同步",
                message: "同步核心在应用前台运行；切到后台后，iOS 可能暂停网络同步。"
            )
            complianceRow(
                systemImage: "network",
                title: "本地网络",
                message: "连接局域网设备时，系统会请求本地网络访问权限。"
            )
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var openSourceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("开源许可证")
                .font(.title3.weight(.bold))

            complianceRow(
                systemImage: "doc.text.fill",
                title: "Syncthing",
                message: "Syncthing core 使用 MPL 2.0 许可证。"
            )
            complianceRow(
                systemImage: "curlybraces",
                title: "Markdown 组件",
                message: "CodeMirror 与 marked 使用 MIT 许可证。"
            )
            Text("正式上架前需要在 App 内提供完整许可证文本和源码链接。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var aboutCard: some View {
        VStack(spacing: 12) {
            infoRow("客户端", value: "SwiftUI foreground core")
            Divider()
            infoRow("版本", value: "0.1.0")
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

    private func complianceRow(systemImage: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
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
        if store.isLoading { return "连接中" }
        if store.errorMessage != nil { return "连接异常" }
        if store.lastConnectedAt != nil { return "已连接" }
        return "未连接"
    }

    private var statusSubtitle: String {
        if store.isLoading { return "正在检查 Syncthing REST API。" }
        if let errorMessage = store.errorMessage { return errorMessage }
        if let lastConnectedAt = store.lastConnectedAt {
            return "上次连接 \(lastConnectedAt.formatted(date: .omitted, time: .shortened))"
        }
        return "请输入 GUI 地址和 API Key。"
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
