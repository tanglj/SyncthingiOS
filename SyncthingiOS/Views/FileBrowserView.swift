import QuickLook
import SwiftUI
import UIKit
import WebKit

struct FileBrowserView: View {
    @EnvironmentObject private var core: SyncthingCoreManager
    @State private var entries: [SharedFileEntry] = []
    @State private var errorMessage: String?
    @State private var previewURL: URL?
    @State private var shareItem: ShareItem?
    @State private var markdownItem: MarkdownItem?

    let folderURL: URL?

    init(folderURL: URL? = nil) {
        self.folderURL = folderURL
    }

    private var currentURL: URL? {
        folderURL ?? core.syncRootURL
    }

    private var title: String {
        guard let folderURL else { return "Files" }
        return folderURL.lastPathComponent
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(folderURL == nil ? .large : .inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            loadEntries()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .onAppear(perform: loadEntries)
                .quickLookPreview($previewURL)
                .sheet(item: $shareItem) { item in
                    ActivityView(activityItems: [item.url])
                }
                .sheet(item: $markdownItem) { item in
                    MarkdownPreviewView(url: item.url)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            stateView(
                "Unable to Open Folder",
                message: errorMessage,
                systemImage: "exclamationmark.folder.fill"
            )
        } else if entries.isEmpty {
            stateView(
                "No Files",
                message: "Synced files will appear in App Documents / Syncthing.",
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
                NavigationLink {
                    FileBrowserView(folderURL: entry.url)
                        .environmentObject(core)
                } label: {
                    rowContent(entry)
                }
            } else {
                Button {
                    open(entry)
                } label: {
                    rowContent(entry)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        shareItem = ShareItem(url: entry.url)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                .contextMenu {
                    Button {
                        open(entry)
                    } label: {
                        Label("Preview", systemImage: "doc.text.magnifyingglass")
                    }

                    Button {
                        shareItem = ShareItem(url: entry.url)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func open(_ entry: SharedFileEntry) {
        if entry.isMarkdown {
            markdownItem = MarkdownItem(url: entry.url)
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
                Label("Refresh", systemImage: "arrow.clockwise")
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
            errorMessage = "The app sync folder is not available yet."
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

private struct MarkdownPreviewView: View {
    let url: URL

    @State private var plainText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Unable to Preview")
                            .font(.title3.weight(.bold))
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else if !plainText.isEmpty {
                    MarkdownWebPreview(
                        markdown: plainText,
                        baseURL: url.deletingLastPathComponent(),
                        title: url.deletingPathExtension().lastPathComponent
                    )
                    .background(Color(.systemBackground))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        do {
            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8) ??
                    String(data: data, encoding: .unicode) else {
                errorMessage = "The file encoding is not supported."
                return
            }
            plainText = content
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MarkdownWebPreview: UIViewRepresentable {
    let markdown: String
    let baseURL: URL
    let title: String

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
        webView.loadHTMLString(MarkdownHTMLDocument.make(markdown: markdown, title: title), baseURL: baseURL)
    }
}

private enum MarkdownHTMLDocument {
    static func make(markdown: String, title: String) -> String {
        let encodedMarkdown = jsonString(markdown)
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
