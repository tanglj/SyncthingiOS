import QuickLook
import SwiftUI
import UIKit
import WebKit

struct FileBrowserView: View {
    @EnvironmentObject private var core: SyncthingCoreManager
    @State private var path: [URL] = []
    @State private var didRestorePath = false

    var body: some View {
        NavigationStack(path: $path) {
            FileBrowserDirectoryView(folderURL: nil)
                .navigationDestination(for: URL.self) { folderURL in
                    FileBrowserDirectoryView(folderURL: folderURL)
                }
        }
        .onAppear(perform: restorePathIfNeeded)
        .onChange(of: path) { _, newPath in
            FileBrowserPathStore.save(folderURL: newPath.last, syncRootURL: core.syncRootURL)
        }
    }

    private func restorePathIfNeeded() {
        guard !didRestorePath else { return }
        didRestorePath = true
        path = FileBrowserPathStore.restoredPath(syncRootURL: core.syncRootURL)
    }
}

private struct FileBrowserDirectoryView: View {
    @EnvironmentObject private var core: SyncthingCoreManager
    @State private var entries: [SharedFileEntry] = []
    @State private var errorMessage: String?
    @State private var previewURL: URL?
    @State private var shareItem: ShareItem?
    @State private var markdownPreviewItem: MarkdownItem?
    @State private var markdownEditorItem: MarkdownItem?
    @State private var newItemName = ""
    @State private var newItemKind: NewItemKind?
    @State private var newItemErrorMessage: String?
    @State private var renameCandidate: SharedFileEntry?
    @State private var renameName = ""
    @State private var renameErrorMessage: String?
    @State private var deleteCandidate: SharedFileEntry?
    @State private var deleteErrorMessage: String?
    @State private var moveCandidate: SharedFileEntry?
    @State private var moveErrorMessage: String?

    let folderURL: URL?

    init(folderURL: URL?) {
        self.folderURL = folderURL
    }

    private var currentURL: URL? {
        folderURL ?? core.syncRootURL
    }

    private var title: String {
        guard let folderURL else { return "文件" }
        return folderURL.lastPathComponent
    }

    private var canCreateItems: Bool {
        folderURL != nil
    }

    private var canDeleteItems: Bool {
        folderURL != nil
    }

    private var canRenameItems: Bool {
        folderURL != nil
    }

    private var canMoveItems: Bool {
        folderURL != nil
    }

    var body: some View {
        content
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(folderURL == nil ? .large : .inline)
            .toolbar { browserToolbar }
            .onAppear(perform: loadEntries)
            .quickLookPreview($previewURL)
            .sheet(item: $shareItem) { item in
                ActivityView(activityItems: [item.url])
            }
            .sheet(item: $markdownPreviewItem, onDismiss: loadEntries) { item in
                MarkdownPreviewView(url: item.url)
            }
            .sheet(item: $markdownEditorItem, onDismiss: loadEntries) { item in
                MarkdownEditorView(url: item.url)
            }
            .modifier(NewItemAlerts(
                kind: newItemKind,
                name: $newItemName,
                isCreating: newItemAlertBinding,
                errorMessage: newItemErrorMessage,
                isErrorPresented: newItemErrorBinding,
                onCancel: resetNewItemInput,
                onCreate: submitNewItem
            ))
            .modifier(RenameItemAlerts(
                candidate: $renameCandidate,
                name: $renameName,
                isRenaming: renameAlertBinding,
                errorMessage: renameErrorMessage,
                isErrorPresented: renameErrorBinding,
                onCancel: resetRenameInput,
                onRename: submitRename
            ))
            .modifier(DeleteItemAlerts(
                candidate: $deleteCandidate,
                isDeleteConfirmationPresented: deleteConfirmationBinding,
                errorMessage: deleteErrorMessage,
                isErrorPresented: deleteErrorBinding,
                onDelete: delete
            ))
            .sheet(item: $moveCandidate) { item in
                MoveDestinationPicker(
                    movingEntry: item,
                    currentFolderURL: currentURL,
                    syncRootURL: core.syncRootURL,
                    onCancel: {
                        moveCandidate = nil
                    },
                    onMove: { destinationURL in
                        move(item, to: destinationURL)
                    }
                )
            }
            .alert("无法移动", isPresented: moveErrorBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(moveErrorMessage ?? "")
            }
    }

    @ToolbarContentBuilder
    private var browserToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if canCreateItems {
                Menu {
                    Button {
                        beginCreating(.folder)
                    } label: {
                        Label("文件夹", systemImage: "folder.badge.plus")
                    }

                    Button {
                        beginCreating(.markdownFile)
                    } label: {
                        Label("Markdown 文件", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建")
            }

            Button {
                loadEntries()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    private var newItemAlertBinding: Binding<Bool> {
        Binding {
            newItemKind != nil
        } set: { isPresented in
            if !isPresented {
                resetNewItemInput()
            }
        }
    }

    private var newItemErrorBinding: Binding<Bool> {
        Binding {
            newItemErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                newItemErrorMessage = nil
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding {
            renameCandidate != nil
        } set: { isPresented in
            if !isPresented {
                resetRenameInput()
            }
        }
    }

    private var renameErrorBinding: Binding<Bool> {
        Binding {
            renameErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                renameErrorMessage = nil
            }
        }
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding {
            deleteErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                deleteErrorMessage = nil
            }
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding {
            deleteCandidate != nil
        } set: { isPresented in
            if !isPresented {
                deleteCandidate = nil
            }
        }
    }

    private var moveErrorBinding: Binding<Bool> {
        Binding {
            moveErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                moveErrorMessage = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            stateView(
                "无法打开文件夹",
                message: errorMessage,
                systemImage: "exclamationmark.folder.fill"
            )
        } else if entries.isEmpty {
            stateView(
                "暂无文件",
                message: "同步文件会显示在我的iPhone / Syncthing 中。",
                systemImage: "folder"
            )
        } else {
            List {
                Section {
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                loadEntries()
            }
        }
    }

    private func entryRow(_ entry: SharedFileEntry) -> some View {
        Group {
            if entry.isDirectory {
                NavigationLink(value: entry.url) {
                    rowContent(entry)
                }
                .modifier(FileActionSwipeActions(
                    entry: entry,
                    isEnabled: canRenameItems || canDeleteItems || canMoveItems,
                    onMove: beginMoving,
                    onRename: beginRenaming,
                    onDelete: { deleteCandidate = $0 }
                ))
            } else {
                HStack(spacing: 10) {
                    Button {
                        open(entry)
                    } label: {
                        rowContent(entry)
                    }
                    .buttonStyle(.plain)

                    if entry.isMarkdown {
                        Button {
                            markdownEditorItem = MarkdownItem(url: entry.url)
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.title2)
                                .foregroundStyle(.teal)
                                .frame(width: 38, height: 38)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("编辑")
                    }
                }
                .modifier(FileActionSwipeActions(
                    entry: entry,
                    isEnabled: canRenameItems || canDeleteItems || canMoveItems,
                    onMove: beginMoving,
                    onRename: beginRenaming,
                    onDelete: { deleteCandidate = $0 }
                ))
            }
        }
    }

    private func open(_ entry: SharedFileEntry) {
        if entry.isMarkdown {
            markdownPreviewItem = MarkdownItem(url: entry.url)
        } else {
            previewURL = entry.url
        }
    }

    private func rowContent(_ entry: SharedFileEntry) -> some View {
        HStack(spacing: 13) {
            Image(systemName: entry.symbolName)
                .font(.title3)
                .foregroundStyle(entry.tint)
                .frame(width: 32, height: 32)
                .background(entry.tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(entry.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func stateView(_ title: String, message: String, systemImage: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.bold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                loadEntries()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .font(.headline)
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func loadEntries() {
        guard let currentURL else {
            entries = []
            errorMessage = "应用同步文件夹暂不可用。"
            return
        }

        do {
            try FileManager.default.createDirectory(at: currentURL, withIntermediateDirectories: true)
            let resourceKeys: Set<URLResourceKey> = [
                .contentModificationDateKey,
                .fileSizeKey,
                .isDirectoryKey,
                .isHiddenKey,
                .nameKey
            ]
            let urls = try FileManager.default.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsPackageDescendants]
            )
            entries = try urls.compactMap { url in
                let values = try url.resourceValues(forKeys: resourceKeys)
                if values.isHidden == true { return nil }
                return SharedFileEntry(url: url, values: values)
            }
            .sorted()
            errorMessage = nil
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }

    private func createItem(named rawName: String, kind: NewItemKind) throws {
        guard let currentURL else {
            throw NewItemError("当前文件夹不可用。")
        }

        let name = normalizedName(rawName, kind: kind)
        guard !name.isEmpty else {
            throw NewItemError("名称不能为空。")
        }
        guard !name.contains("/") && !name.contains(":") else {
            throw NewItemError("名称不能包含路径分隔符。")
        }

        let url = currentURL.appendingPathComponent(name, isDirectory: kind == .folder)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw NewItemError("同名项目已存在。")
        }

        switch kind {
        case .folder:
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        case .markdownFile:
            try Data().write(to: url, options: .atomic)
        }
        loadEntries()
    }

    private func rename(_ entry: SharedFileEntry, to rawName: String) {
        do {
            try renameItem(entry, to: rawName)
            loadEntries()
        } catch {
            renameErrorMessage = error.localizedDescription
        }
    }

    private func renameItem(_ entry: SharedFileEntry, to rawName: String) throws {
        guard canRenameItems else {
            throw FileOperationError("顶层目录不支持重命名。")
        }
        guard let currentURL else {
            throw FileOperationError("当前文件夹不可用。")
        }

        let name = normalizedRenameName(rawName, for: entry)
        guard !name.isEmpty else {
            throw FileOperationError("名称不能为空。")
        }
        guard !name.contains("/") && !name.contains(":") else {
            throw FileOperationError("名称不能包含路径分隔符。")
        }
        guard name != entry.name else { return }

        let parentPath = currentURL.standardizedFileURL.path
        let sourceURL = entry.url.standardizedFileURL
        guard sourceURL.deletingLastPathComponent().path == parentPath else {
            throw FileOperationError("只能重命名当前文件夹内的项目。")
        }

        let targetURL = currentURL
            .appendingPathComponent(name, isDirectory: entry.isDirectory)
            .standardizedFileURL
        guard !FileManager.default.fileExists(atPath: targetURL.path) else {
            throw FileOperationError("同名项目已存在。")
        }

        try FileManager.default.moveItem(at: sourceURL, to: targetURL)
    }

    private func delete(_ entry: SharedFileEntry) {
        do {
            try deleteItem(entry)
            loadEntries()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }

    private func deleteItem(_ entry: SharedFileEntry) throws {
        guard canDeleteItems else {
            throw FileOperationError("顶层目录不支持删除。")
        }
        guard let currentURL else {
            throw FileOperationError("当前文件夹不可用。")
        }

        let parentPath = currentURL.standardizedFileURL.path
        let targetURL = entry.url.standardizedFileURL
        guard targetURL.deletingLastPathComponent().path == parentPath else {
            throw FileOperationError("只能删除当前文件夹内的项目。")
        }

        try FileManager.default.removeItem(at: targetURL)
    }

    private func move(_ entry: SharedFileEntry, to destinationURL: URL) {
        do {
            try moveItem(entry, to: destinationURL)
            moveCandidate = nil
            loadEntries()
        } catch {
            moveCandidate = nil
            moveErrorMessage = error.localizedDescription
        }
    }

    private func moveItem(_ entry: SharedFileEntry, to destinationURL: URL) throws {
        guard canMoveItems else {
            throw FileOperationError("顶层目录不支持移动。")
        }
        guard let currentURL else {
            throw FileOperationError("当前文件夹不可用。")
        }
        guard let syncRootURL = core.syncRootURL?.standardizedFileURL else {
            throw FileOperationError("同步根目录不可用。")
        }

        let parentPath = currentURL.standardizedFileURL.path
        let sourceURL = entry.url.standardizedFileURL
        guard sourceURL.deletingLastPathComponent().path == parentPath else {
            throw FileOperationError("只能移动当前文件夹内的项目。")
        }

        let destinationURL = destinationURL.standardizedFileURL
        guard MoveDestinationPolicy.isDirectory(destinationURL),
              MoveDestinationPolicy.isInsideSyncRoot(destinationURL, syncRootURL: syncRootURL) else {
            throw FileOperationError("请选择同步目录内的文件夹。")
        }
        guard MoveDestinationPolicy.canMove(entry, to: destinationURL, syncRootURL: syncRootURL) else {
            throw FileOperationError("不能移动到当前项目或其子文件夹中。")
        }

        let targetURL = destinationURL
            .appendingPathComponent(entry.name, isDirectory: entry.isDirectory)
            .standardizedFileURL
        guard targetURL.path != sourceURL.path else { return }
        guard !FileManager.default.fileExists(atPath: targetURL.path) else {
            throw FileOperationError("目标文件夹中已存在同名项目。")
        }

        try FileManager.default.moveItem(at: sourceURL, to: targetURL)
    }

    private func beginRenaming(_ entry: SharedFileEntry) {
        renameName = editableRenameName(for: entry)
        renameCandidate = entry
    }

    private func beginMoving(_ entry: SharedFileEntry) {
        moveCandidate = entry
    }

    private func submitRename() {
        guard let renameCandidate else { return }
        rename(renameCandidate, to: renameName)
        resetRenameInput()
    }

    private func resetRenameInput() {
        renameName = ""
        renameCandidate = nil
    }

    private func beginCreating(_ kind: NewItemKind) {
        newItemName = ""
        newItemKind = kind
    }

    private func submitNewItem() {
        guard let newItemKind else { return }
        do {
            try createItem(named: newItemName, kind: newItemKind)
            resetNewItemInput()
        } catch {
            resetNewItemInput()
            newItemErrorMessage = error.localizedDescription
        }
    }

    private func resetNewItemInput() {
        newItemName = ""
        newItemKind = nil
    }

    private func normalizedName(_ rawName: String, kind: NewItemKind) -> String {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .markdownFile && !hasMarkdownExtension(name) {
            name += ".md"
        }
        return name
    }

    private func normalizedRenameName(_ rawName: String, for entry: SharedFileEntry) -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.isMarkdown {
            guard !name.isEmpty else { return "" }
            return name + "." + entry.url.pathExtension
        }
        return name
    }

    private func editableRenameName(for entry: SharedFileEntry) -> String {
        if entry.isMarkdown {
            return entry.url.deletingPathExtension().lastPathComponent
        }
        return entry.name
    }

    private func hasMarkdownExtension(_ name: String) -> Bool {
        let lowercasedName = name.lowercased()
        return lowercasedName.hasSuffix(".md") || lowercasedName.hasSuffix(".markdown")
    }
}

private enum NewItemKind: String, Identifiable {
    case folder
    case markdownFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .folder:
            return "新建文件夹"
        case .markdownFile:
            return "新建 Markdown 文件"
        }
    }

    var placeholder: String {
        switch self {
        case .folder:
            return "文件夹名称"
        case .markdownFile:
            return "文件名称"
        }
    }
}

private struct NewItemAlerts: ViewModifier {
    let kind: NewItemKind?
    @Binding var name: String
    let isCreating: Binding<Bool>
    let errorMessage: String?
    let isErrorPresented: Binding<Bool>
    let onCancel: () -> Void
    let onCreate: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(kind?.title ?? "新建", isPresented: isCreating) {
                TextField(kind?.placeholder ?? "名称", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("取消", role: .cancel) {
                    onCancel()
                }
                Button("创建") {
                    onCreate()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert("无法创建", isPresented: isErrorPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

private struct RenameItemAlerts: ViewModifier {
    @Binding var candidate: SharedFileEntry?
    @Binding var name: String
    let isRenaming: Binding<Bool>
    let errorMessage: String?
    let isErrorPresented: Binding<Bool>
    let onCancel: () -> Void
    let onRename: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("重命名", isPresented: isRenaming) {
                TextField("名称", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("取消", role: .cancel) {
                    onCancel()
                }
                Button("保存") {
                    onRename()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text(candidate?.name ?? "")
            }
            .alert("无法重命名", isPresented: isErrorPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

private struct DeleteItemAlerts: ViewModifier {
    @Binding var candidate: SharedFileEntry?
    let isDeleteConfirmationPresented: Binding<Bool>
    let errorMessage: String?
    let isErrorPresented: Binding<Bool>
    let onDelete: (SharedFileEntry) -> Void

    func body(content: Content) -> some View {
        content
            .alert("删除项目？", isPresented: isDeleteConfirmationPresented) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let candidate {
                        onDelete(candidate)
                    }
                }
            } message: {
                Text("将删除“\(candidate?.name ?? "")”。此操作不可撤销。")
            }
            .alert("无法删除", isPresented: isErrorPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

private struct MoveDestinationPicker: View {
    @Environment(\.dismiss) private var dismiss

    let movingEntry: SharedFileEntry
    let currentFolderURL: URL?
    let syncRootURL: URL?
    let onCancel: () -> Void
    let onMove: (URL) -> Void

    @State private var path: [URL] = []

    private var destinationRootURL: URL? {
        MoveDestinationPolicy.topLevelSyncFolderURL(
            currentFolderURL: currentFolderURL,
            syncRootURL: syncRootURL
        ) ?? syncRootURL?.standardizedFileURL
    }

    var body: some View {
        NavigationStack(path: $path) {
            MoveDestinationDirectoryView(
                movingEntry: movingEntry,
                directoryURL: destinationRootURL,
                syncRootURL: destinationRootURL,
                onMove: handleMove
            )
            .navigationDestination(for: URL.self) { directoryURL in
                MoveDestinationDirectoryView(
                    movingEntry: movingEntry,
                    directoryURL: directoryURL,
                    syncRootURL: destinationRootURL,
                    onMove: handleMove
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") {
                    onCancel()
                    dismiss()
                }
            }
        }
    }

    private func handleMove(_ destinationURL: URL) {
        onMove(destinationURL)
        dismiss()
    }
}

private struct MoveDestinationDirectoryView: View {
    let movingEntry: SharedFileEntry
    let directoryURL: URL?
    let syncRootURL: URL?
    let onMove: (URL) -> Void

    @State private var directories: [MoveDestinationEntry] = []
    @State private var errorMessage: String?

    private var title: String {
        guard let directoryURL, directoryURL != syncRootURL else { return "选择目标文件夹" }
        return directoryURL.lastPathComponent
    }

    private var canMoveHere: Bool {
        guard let directoryURL, let syncRootURL else { return false }
        return MoveDestinationPolicy.canMove(movingEntry, to: directoryURL, syncRootURL: syncRootURL)
    }

    var body: some View {
        content
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("移动到此处") {
                        if let directoryURL {
                            onMove(directoryURL)
                        }
                    }
                    .disabled(!canMoveHere)
                }
            }
            .onAppear(perform: loadDirectories)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.folder.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("无法打开文件夹")
                    .font(.title3.weight(.bold))
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    loadDirectories()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if directories.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "folder")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("没有子文件夹")
                    .font(.title3.weight(.bold))
                Text(canMoveHere ? "可以直接移动到当前文件夹。" : "当前文件夹不能作为移动目标。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(directories) { entry in
                        NavigationLink(value: entry.url) {
                            HStack(spacing: 13) {
                                Image(systemName: "folder.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                                    .frame(width: 32, height: 32)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(entry.name)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                loadDirectories()
            }
        }
    }

    private func loadDirectories() {
        guard let directoryURL else {
            directories = []
            errorMessage = "同步根目录暂不可用。"
            return
        }

        do {
            let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .nameKey]
            let urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsPackageDescendants]
            )
            directories = try urls.compactMap { url in
                let values = try url.resourceValues(forKeys: resourceKeys)
                guard values.isDirectory == true, values.isHidden != true else { return nil }
                let entry = MoveDestinationEntry(url: url, name: values.name ?? url.lastPathComponent)
                guard MoveDestinationPolicy.canBrowse(entry.url, movingEntry: movingEntry) else { return nil }
                return entry
            }
            .sorted()
            errorMessage = nil
        } catch {
            directories = []
            errorMessage = error.localizedDescription
        }
    }
}

private enum MoveDestinationPolicy {
    static func topLevelSyncFolderURL(currentFolderURL: URL?, syncRootURL: URL?) -> URL? {
        guard let currentFolderURL, let syncRootURL else { return nil }

        let rootURL = syncRootURL.standardizedFileURL
        let currentURL = currentFolderURL.standardizedFileURL
        let rootPath = rootURL.path
        let currentPath = currentURL.path
        guard currentPath.hasPrefix(rootPath + "/") else { return nil }

        guard let firstComponent = currentPath
            .dropFirst(rootPath.count + 1)
            .split(separator: "/", omittingEmptySubsequences: true)
            .first else {
            return nil
        }

        let topLevelURL = rootURL
            .appendingPathComponent(String(firstComponent), isDirectory: true)
            .standardizedFileURL
        guard isDirectory(topLevelURL) else { return nil }
        return topLevelURL
    }

    static func canBrowse(_ directoryURL: URL, movingEntry: SharedFileEntry) -> Bool {
        let directoryPath = directoryURL.standardizedFileURL.path
        let sourcePath = movingEntry.url.standardizedFileURL.path
        if movingEntry.isDirectory {
            return directoryPath != sourcePath && !directoryPath.hasPrefix(sourcePath + "/")
        }
        return true
    }

    static func canMove(_ entry: SharedFileEntry, to destinationURL: URL, syncRootURL: URL) -> Bool {
        let destinationURL = destinationURL.standardizedFileURL
        let sourceURL = entry.url.standardizedFileURL

        guard isDirectory(destinationURL),
              isInsideSyncRoot(destinationURL, syncRootURL: syncRootURL) else {
            return false
        }

        let sourceParentPath = sourceURL.deletingLastPathComponent().path
        if destinationURL.path == sourceParentPath {
            return false
        }

        if entry.isDirectory {
            return destinationURL.path != sourceURL.path && !destinationURL.path.hasPrefix(sourceURL.path + "/")
        }
        return true
    }

    static func isInsideSyncRoot(_ directoryURL: URL, syncRootURL: URL) -> Bool {
        let directoryPath = directoryURL.standardizedFileURL.path
        let rootPath = syncRootURL.standardizedFileURL.path
        return directoryPath == rootPath || directoryPath.hasPrefix(rootPath + "/")
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private struct MoveDestinationEntry: Identifiable, Comparable {
    let url: URL
    let name: String

    var id: URL { url }

    static func < (lhs: MoveDestinationEntry, rhs: MoveDestinationEntry) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

private struct FileActionSwipeActions: ViewModifier {
    let entry: SharedFileEntry
    let isEnabled: Bool
    let onMove: (SharedFileEntry) -> Void
    let onRename: (SharedFileEntry) -> Void
    let onDelete: (SharedFileEntry) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        onDelete(entry)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }

                    Button {
                        onMove(entry)
                    } label: {
                        Label("移动", systemImage: "folder")
                    }
                    .tint(.indigo)

                    Button {
                        onRename(entry)
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
        } else {
            content
        }
    }
}

private struct FileOperationError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private typealias NewItemError = FileOperationError

private enum FileBrowserPathStore {
    private static let key = "syncthing.files.lastDirectoryPath"

    static func save(folderURL: URL?, syncRootURL: URL?) {
        guard let folderURL,
              let relativePath = relativeDirectoryPath(for: folderURL, syncRootURL: syncRootURL) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(relativePath, forKey: key)
    }

    static func restoredPath(syncRootURL: URL?) -> [URL] {
        guard let syncRootURL,
              let storedPath = UserDefaults.standard.string(forKey: key),
              !storedPath.isEmpty else {
            return []
        }

        let rootURL = syncRootURL.standardizedFileURL
        var restoredPath: [URL] = []
        var currentURL = rootURL

        for component in storedPath.split(separator: "/", omittingEmptySubsequences: true) {
            let decodedComponent = String(component).removingPercentEncoding ?? String(component)
            guard isValidPathComponent(decodedComponent) else {
                break
            }

            let nextURL = currentURL.appendingPathComponent(decodedComponent, isDirectory: true).standardizedFileURL
            guard isExistingDirectory(nextURL) else {
                break
            }

            restoredPath.append(nextURL)
            currentURL = nextURL
        }

        if restoredPath.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let lastURL = restoredPath.last,
                  let relativePath = relativeDirectoryPath(for: lastURL, syncRootURL: syncRootURL),
                  relativePath != storedPath {
            UserDefaults.standard.set(relativePath, forKey: key)
        }

        return restoredPath
    }

    private static func relativeDirectoryPath(for folderURL: URL, syncRootURL: URL?) -> String? {
        guard let syncRootURL else { return nil }

        let rootPath = syncRootURL.standardizedFileURL.path
        let folderPath = folderURL.standardizedFileURL.path

        guard folderPath != rootPath else { return nil }
        guard folderPath.hasPrefix(rootPath + "/") else { return nil }

        let relativePath = String(folderPath.dropFirst(rootPath.count + 1))
        guard !relativePath.isEmpty,
              relativePath.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                  isValidPathComponent(String($0))
              }) else {
            return nil
        }

        return relativePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
    }

    private static func isValidPathComponent(_ component: String) -> Bool {
        !component.isEmpty && component != "." && component != ".." && !component.contains("/")
    }

    private static func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private struct SharedFileEntry: Identifiable, Comparable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modifiedAt: Date?

    init(url: URL, values: URLResourceValues) {
        self.id = url
        self.url = url
        self.name = values.name ?? url.lastPathComponent
        self.isDirectory = values.isDirectory == true
        self.size = values.fileSize.map(Int64.init)
        self.modifiedAt = values.contentModificationDate
    }

    var symbolName: String {
        if isDirectory { return "folder.fill" }
        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            return "text.alignleft"
        case "txt", "log", "json", "xml", "yaml", "yml":
            return "doc.text.fill"
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return "photo.fill"
        case "mp4", "mov", "m4v":
            return "film.fill"
        case "mp3", "m4a", "wav", "flac":
            return "waveform"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "gz", "tar", "7z":
            return "archivebox.fill"
        default:
            return "doc.fill"
        }
    }

    var tint: Color {
        if isDirectory { return .blue }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return .pink
        case "mp4", "mov", "m4v", "mp3", "m4a", "wav", "flac":
            return .purple
        case "pdf":
            return .red
        case "md", "markdown":
            return .teal
        case "txt", "log", "json", "xml", "yaml", "yml":
            return .green
        default:
            return .secondary
        }
    }

    var isMarkdown: Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    var detailText: String {
        var parts: [String] = []
        if isDirectory {
            parts.append("Folder")
        } else if let size {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        } else {
            parts.append("File")
        }
        if let modifiedAt {
            parts.append(modifiedAt.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: " - ")
    }

    static func < (lhs: SharedFileEntry, rhs: SharedFileEntry) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ShareItem: Identifiable {
    let url: URL

    var id: URL { url }
}

private struct MarkdownItem: Identifiable {
    let url: URL

    var id: URL { url }
}

private struct MarkdownEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL

    @State private var text = ""
    @State private var savedText = ""
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isSaving = false

    private var hasUnsavedChanges: Bool {
        text != savedText
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, text.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("无法编辑")
                            .font(.title3.weight(.bold))
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
                    VStack(spacing: 0) {
                        if let errorMessage {
                            Label {
                                Text(errorMessage)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12))
                        }

                        CodeMirrorMarkdownEditor(text: $text)
                    }
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .foregroundStyle(.secondary)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("保存", systemImage: "checkmark")
                                .labelStyle(.titleAndIcon)
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(.green)
                    .disabled(isLoading || isSaving || !hasUnsavedChanges)
                }
            }
            .onAppear(perform: loadMarkdown)
        }
    }

    private func loadMarkdown() {
        guard isLoading else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8) ??
                    String(data: data, encoding: .unicode) else {
                errorMessage = "不支持该文件编码。"
                isLoading = false
                return
            }
            text = content
            savedText = content
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            guard let data = text.data(using: .utf8) else {
                errorMessage = "不支持该文件编码。"
                return
            }
            try data.write(to: url, options: .atomic)
            savedText = text
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CodeMirrorMarkdownEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "editor")

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.webView = webView
        webView.loadHTMLString(CodeMirrorHTMLDocument.make(markdown: text), baseURL: CodeMirrorHTMLDocument.baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.text = $text
        guard context.coordinator.didFinishLoading else { return }
        guard context.coordinator.lastEditorText != text else { return }
        let encodedText = CodeMirrorHTMLDocument.jsonString(text)
        webView.evaluateJavaScript("window.setMarkdown(\(encodedText));")
        context.coordinator.lastEditorText = text
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var text: Binding<String>
        weak var webView: WKWebView?
        var didFinishLoading = false
        var lastEditorText = ""

        init(text: Binding<String>) {
            self.text = text
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishLoading = true
            lastEditorText = text.wrappedValue
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "editor",
                  let payload = message.body as? [String: Any],
                  let kind = payload["type"] as? String else {
                return
            }

            if kind == "change", let value = payload["value"] as? String {
                lastEditorText = value
                text.wrappedValue = value
            }
        }
    }
}

private enum CodeMirrorHTMLDocument {
    static var baseURL: URL? {
        Bundle.main.url(forResource: "codemirror", withExtension: "js", subdirectory: "MarkdownEditor")?
            .deletingLastPathComponent()
    }

    static func make(markdown: String) -> String {
        let encodedMarkdown = jsonString(markdown)
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <link rel="stylesheet" href="codemirror.css">
        <style>
        :root {
            color-scheme: light dark;
            --bg: #ffffff;
            --text: #1f2328;
            --gutter: #f6f8fa;
            --border: #d0d7de;
            --cursor: #0969da;
            --selection: rgba(9, 105, 218, 0.18);
            --line: #f8fafc;
            --quote: #667085;
            --link: #0969da;
            --code: #0a7f51;
            --heading: #1f6feb;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #0d1117;
                --text: #e6edf3;
                --gutter: #161b22;
                --border: #30363d;
                --cursor: #58a6ff;
                --selection: rgba(88, 166, 255, 0.25);
                --line: #111827;
                --quote: #8b949e;
                --link: #58a6ff;
                --code: #7ee787;
                --heading: #79c0ff;
            }
        }
        html, body, #editor {
            width: 100%;
            height: 100%;
            margin: 0;
            overflow: hidden;
            background: var(--bg);
        }
        .CodeMirror {
            width: 100%;
            height: 100%;
            background: var(--bg);
            color: var(--text);
            font: 16px/1.55 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            letter-spacing: 0;
        }
        .CodeMirror-lines {
            padding: 16px 0 max(40px, env(safe-area-inset-bottom));
        }
        .CodeMirror pre.CodeMirror-line,
        .CodeMirror pre.CodeMirror-line-like {
            padding: 0 18px;
        }
        .CodeMirror-gutters {
            background: var(--gutter);
            border-right: 1px solid var(--border);
        }
        .CodeMirror-linenumber {
            color: #8b949e;
            padding: 0 8px 0 10px;
        }
        .CodeMirror-cursor {
            border-left-color: var(--cursor);
        }
        .CodeMirror-selected {
            background: var(--selection) !important;
        }
        .CodeMirror-activeline-background {
            background: var(--line);
        }
        .cm-header {
            color: var(--heading);
            font-weight: 700;
        }
        .cm-strong { font-weight: 700; }
        .cm-em { font-style: italic; }
        .cm-quote { color: var(--quote); }
        .cm-link, .cm-url { color: var(--link); }
        .cm-comment, .cm-string { color: var(--code); }
        </style>
        </head>
        <body>
        <textarea id="editor"></textarea>
        <script src="codemirror.js"></script>
        <script src="xml.js"></script>
        <script src="markdown.js"></script>
        <script src="continuelist.js"></script>
        <script>
        const initialMarkdown = \(encodedMarkdown);
        const textarea = document.getElementById('editor');
        textarea.value = initialMarkdown;

        const editor = CodeMirror.fromTextArea(textarea, {
            mode: {
                name: 'markdown',
                highlightFormatting: true,
                taskLists: true,
                strikethrough: true,
                fencedCodeBlockHighlighting: false
            },
            lineNumbers: true,
            lineWrapping: true,
            indentUnit: 2,
            tabSize: 2,
            extraKeys: {
                Enter: 'newlineAndIndentContinueMarkdownList'
            }
        });

        let applyingExternalValue = false;
        editor.on('change', () => {
            if (applyingExternalValue) return;
            window.webkit.messageHandlers.editor.postMessage({
                type: 'change',
                value: editor.getValue()
            });
        });

        window.setMarkdown = function(value) {
            if (editor.getValue() === value) return;
            applyingExternalValue = true;
            const cursor = editor.getCursor();
            editor.setValue(value);
            editor.setCursor(cursor);
            applyingExternalValue = false;
        };

        window.focusEditor = function() {
            editor.focus();
        };

        setTimeout(() => {
            editor.refresh();
            editor.focus();
        }, 80);
        </script>
        </body>
        </html>
        """
    }

    static func jsonString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              var string = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        string = string.replacingOccurrences(of: "<", with: "\\u003C")
        return string
    }
}

private struct MarkdownPreviewView: View {
    let url: URL

    @State private var plainText = ""
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("无法预览")
                            .font(.title3.weight(.bold))
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else if plainText.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("空 Markdown 文件")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else {
                    MarkdownWebPreview(
                        markdown: plainText,
                        baseURL: url.deletingLastPathComponent(),
                        title: url.deletingPathExtension().lastPathComponent
                    )
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .onAppear(perform: loadMarkdown)
        }
    }

    private func loadMarkdown() {
        isLoading = true
        do {
            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8) ??
                    String(data: data, encoding: .unicode) else {
                errorMessage = "不支持该文件编码。"
                isLoading = false
                return
            }
            plainText = content
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct MarkdownWebPreview: UIViewRepresentable {
    let markdown: String
    let baseURL: URL
    let title: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = MarkdownHTMLDocument.make(markdown: markdown, title: title, baseURL: baseURL)
        context.coordinator.load(html: html, baseURL: baseURL, in: webView)
    }

    final class Coordinator: NSObject {
        private var temporaryURL: URL?

        func load(html: String, baseURL: URL, in webView: WKWebView) {
            do {
                let previewURL = try writePreviewHTML(html)
                temporaryURL = previewURL
                webView.loadFileURL(previewURL, allowingReadAccessTo: previewURL.deletingLastPathComponent())
            } catch {
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        private func writePreviewHTML(_ html: String) throws -> URL {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SyncClientMarkdownPreview", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("html")
            try html.write(to: url, atomically: true, encoding: .utf8)

            if let temporaryURL, temporaryURL != url {
                try? FileManager.default.removeItem(at: temporaryURL)
            }

            return url
        }

        func cleanup() {
            if let temporaryURL {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            temporaryURL = nil
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        coordinator.cleanup()
    }
}

private enum MarkdownHTMLDocument {
    static func make(markdown: String, title: String, baseURL: URL) -> String {
        let encodedMarkdown = jsonString(markdownWithEmbeddedLocalImages(markdown, baseURL: baseURL))
        let encodedTitle = jsonString(title)
        let markedScript = bundledMarkedScript()
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <title></title>
        <style>
        :root {
            color-scheme: light dark;
            --bg: #ffffff;
            --text: #1f2328;
            --muted: #667085;
            --border: #d0d7de;
            --code-bg: #f6f8fa;
            --quote-bg: #f8fafc;
            --link: #0969da;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #0d1117;
                --text: #e6edf3;
                --muted: #8b949e;
                --border: #30363d;
                --code-bg: #161b22;
                --quote-bg: #111827;
                --link: #58a6ff;
            }
        }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            background: var(--bg);
            color: var(--text);
            font: 17px/1.62 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
            overflow-wrap: break-word;
            -webkit-text-size-adjust: 100%;
        }
        main {
            width: min(100%, 780px);
            margin: 0 auto;
            padding: 22px 20px max(42px, env(safe-area-inset-bottom));
        }
        h1, h2, h3, h4, h5, h6 {
            margin: 1.2em 0 0.45em;
            line-height: 1.24;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif;
        }
        h1 { font-size: 2rem; padding-bottom: 0.32em; border-bottom: 1px solid var(--border); }
        h2 { font-size: 1.55rem; padding-bottom: 0.24em; border-bottom: 1px solid var(--border); }
        h3 { font-size: 1.25rem; }
        p { margin: 0.78em 0; }
        a { color: var(--link); text-decoration-thickness: 0.08em; text-underline-offset: 0.18em; }
        ul, ol { margin: 0.75em 0; padding-left: 1.5em; }
        li { margin: 0.35em 0; }
        li > ul, li > ol { margin: 0.25em 0; }
        blockquote {
            margin: 1em 0;
            padding: 0.75em 1em;
            color: var(--muted);
            background: var(--quote-bg);
            border-left: 4px solid var(--border);
            border-radius: 8px;
        }
        pre {
            margin: 1em 0;
            padding: 14px;
            overflow: auto;
            background: var(--code-bg);
            border: 1px solid var(--border);
            border-radius: 8px;
            -webkit-overflow-scrolling: touch;
        }
        code {
            font: 0.92em/1.5 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            background: var(--code-bg);
            border-radius: 5px;
            padding: 0.15em 0.35em;
        }
        pre code { padding: 0; background: transparent; border-radius: 0; white-space: pre; }
        table {
            display: block;
            width: 100%;
            overflow-x: auto;
            border-collapse: collapse;
            margin: 1em 0;
            -webkit-overflow-scrolling: touch;
        }
        th, td { border: 1px solid var(--border); padding: 8px 10px; text-align: left; }
        th { background: var(--code-bg); font-weight: 700; }
        img { max-width: 100%; height: auto; border-radius: 8px; }
        hr { border: 0; border-top: 1px solid var(--border); margin: 1.6em 0; }
        input[type="checkbox"] { width: 1.05em; height: 1.05em; margin-right: 0.45em; vertical-align: -0.15em; }
        </style>
        </head>
        <body>
        <main id="content"></main>
        <script>
        \(markedScript)
        </script>
        <script>
        const markdownSource = \(encodedMarkdown);
        document.title = \(encodedTitle);

        marked.setOptions({
            async: false,
            breaks: false,
            gfm: true,
            pedantic: false,
            silent: true
        });

        function sanitizePreview(root) {
            root.querySelectorAll('script, iframe, object, embed, style, link[rel="stylesheet"]').forEach(node => node.remove());
            root.querySelectorAll('*').forEach(node => {
                [...node.attributes].forEach(attribute => {
                    const name = attribute.name.toLowerCase();
                    const value = attribute.value.trim().toLowerCase();
                    if (name.startsWith('on') || value.startsWith('javascript:')) {
                        node.removeAttribute(attribute.name);
                    }
                });
            });
        }

        const content = document.getElementById('content');
        content.innerHTML = marked.parse(markdownSource);
        sanitizePreview(content);

        content.querySelectorAll('a').forEach(link => {
            link.rel = 'noopener noreferrer';
        });

        content.querySelectorAll('input[type="checkbox"]').forEach(input => {
            input.disabled = true;
        });
        </script>
        </body>
        </html>
        """
    }

    private static func markdownWithEmbeddedLocalImages(_ markdown: String, baseURL: URL) -> String {
        var result = ""
        var cursor = markdown.startIndex

        while let imageStart = markdown[cursor...].range(of: "![")?.lowerBound {
            guard let labelEnd = markdown[imageStart...].firstIndex(of: "]") else { break }
            let openParen = markdown.index(after: labelEnd)
            guard openParen < markdown.endIndex, markdown[openParen] == "(",
                  let closeParen = markdown[openParen...].firstIndex(of: ")") else {
                cursor = markdown.index(after: imageStart)
                continue
            }

            let destinationStart = markdown.index(after: openParen)
            let rawDestination = String(markdown[destinationStart..<closeParen])
            guard let embeddedDestination = embeddedImageDestination(rawDestination, baseURL: baseURL) else {
                cursor = markdown.index(after: imageStart)
                continue
            }

            result += markdown[cursor..<destinationStart]
            result += embeddedDestination
            cursor = closeParen
        }

        result += markdown[cursor...]
        return result
    }

    private static func embeddedImageDestination(_ rawDestination: String, baseURL: URL) -> String? {
        let trimmed = rawDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              !trimmed.hasPrefix("//"),
              !trimmed.contains(where: { $0.isWhitespace }),
              trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) == nil,
              !trimmed.hasPrefix("/") else {
            return nil
        }

        let pathOnly = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        guard !pathOnly.isEmpty,
              let decodedPath = String(pathOnly).removingPercentEncoding else {
            return nil
        }

        let resourceURL = baseURL
            .appendingPathComponent(decodedPath)
            .standardizedFileURL
        guard isReadableImageResource(resourceURL, under: baseURL),
              let data = try? Data(contentsOf: resourceURL) else {
            return nil
        }

        return "data:\(mimeType(for: resourceURL));base64,\(data.base64EncodedString())"
    }

    private static func isReadableImageResource(_ url: URL, under baseURL: URL) -> Bool {
        let basePath = baseURL.standardizedFileURL.path
        let resourcePath = url.standardizedFileURL.path
        guard resourcePath.hasPrefix(basePath + "/"),
              supportedImageExtensions.contains(url.pathExtension.lowercased()) else {
            return false
        }

        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: resourcePath, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private static let supportedImageExtensions: Set<String> = [
        "apng", "avif", "gif", "heic", "heif", "jpg", "jpeg", "png", "svg", "webp"
    ]

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "apng": return "image/apng"
        case "avif": return "image/avif"
        case "gif": return "image/gif"
        case "heic", "heif": return "image/heic"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }

    private static func bundledMarkedScript() -> String {
        guard let url = Bundle.main.url(
            forResource: "marked.min",
            withExtension: "js",
            subdirectory: "MarkdownPreview"
        ),
        let script = try? String(contentsOf: url, encoding: .utf8) else {
            return """
            window.marked = {
                setOptions: function() {},
                parse: function(source) {
                    const escapeHTML = value => value.replace(/[&<>"']/g, ch => ({
                        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
                    }[ch]));
                    return '<pre><code>' + escapeHTML(source) + '</code></pre>';
                }
            }
            """
        }
        return script.replacingOccurrences(of: "</script>", with: "<\\/script>")
    }

    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return string
    }
}
