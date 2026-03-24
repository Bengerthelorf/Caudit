import SwiftUI
import WebKit

/// Embedded browser for signing into Claude.ai to extract session cookie.
struct BrowserSignInView: NSViewRepresentable {
    let onSessionKey: (String, Date?) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView

        // Start polling for cookie as reliable fallback
        context.coordinator.startPolling()

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSessionKey: onSessionKey)
    }

    /// Clean up stored website data after sign-in is complete.
    static func cleanupWebData() {
        let dataStore = WKWebsiteDataStore.default()
        let types: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
        ]
        dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onSessionKey: (String, Date?) -> Void
        private let targetDomain = "claude.ai"
        private var foundCookie = false
        weak var webView: WKWebView?
        private var pollTimer: Timer?

        init(onSessionKey: @escaping (String, Date?) -> Void) {
            self.onSessionKey = onSessionKey
        }

        deinit {
            pollTimer?.invalidate()
        }

        /// Poll cookies every 2 seconds — most reliable detection across all login flows.
        func startPolling() {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.checkCookies()
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkCookies()
        }

        // MARK: - WKUIDelegate

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // MARK: - Cookie Detection

        private func checkCookies() {
            guard !foundCookie, let webView else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.foundCookie else { return }
                for cookie in cookies {
                    if cookie.name == "sessionKey" && cookie.domain.contains(self.targetDomain) {
                        self.foundCookie = true
                        self.pollTimer?.invalidate()
                        self.pollTimer = nil
                        let key = cookie.value
                        let expiry = cookie.expiresDate
                        DispatchQueue.main.async {
                            self.onSessionKey(key, expiry)
                        }
                        return
                    }
                }
            }
        }
    }
}
