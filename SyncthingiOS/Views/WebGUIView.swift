import SwiftUI
import WebKit

struct WebGUIView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            SyncthingWebView(url: settings.snapshot.baseURL)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("网页管理")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SyncthingWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
