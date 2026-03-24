import SwiftUI
import WebKit

/// Embedded browser for signing into Claude.ai to extract session cookie.
struct BrowserSignInView: NSViewRepresentable {
    let onSessionKey: (String, Date?) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Use default (persistent) data store — nonPersistent does not reliably
        // expose cookies via getAllCookies/cookiesDidChange in practice.
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Watch for cookie changes in real-time
        config.websiteDataStore.httpCookieStore.add(context.coordinator)

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return webView
    }

    /// Clean up stored website data after sign-in is complete.
    static func cleanupWebData() {
        let dataStore = WKWebsiteDataStore.default()
        let types: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases,
        ]
        dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSessionKey: onSessionKey)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        let onSessionKey: (String, Date?) -> Void
        private let targetDomain = "claude.ai"
        private var foundCookie = false
        private weak var webView: WKWebView?

        init(onSessionKey: @escaping (String, Date?) -> Void) {
            self.onSessionKey = onSessionKey
        }

        // MARK: - WKHTTPCookieStoreObserver

        /// Fires whenever any cookie in the store changes — most reliable detection method.
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard !foundCookie else { return }
            cookieStore.getAllCookies { [weak self] cookies in
                self?.processCookies(cookies)
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            guard !foundCookie else { return }
            checkForSessionCookie(webView: webView)
        }

        // MARK: - WKUIDelegate

        /// Handle Google SSO popups by loading in the same webview.
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

        // MARK: - Cookie Extraction

        private func checkForSessionCookie(webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                self?.processCookies(cookies)
            }
        }

        private func processCookies(_ cookies: [HTTPCookie]) {
            guard !foundCookie else { return }
            for cookie in cookies {
                if cookie.name == "sessionKey" && cookie.domain.contains(targetDomain) {
                    foundCookie = true
                    let key = cookie.value
                    let expiry = cookie.expiresDate
                    DispatchQueue.main.async { [weak self] in
                        self?.onSessionKey(key, expiry)
                    }
                    return
                }
            }
        }
    }
}
