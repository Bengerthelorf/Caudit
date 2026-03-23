import SwiftUI
import WebKit

/// Embedded browser for signing into Claude.ai to extract session cookie.
struct BrowserSignInView: NSViewRepresentable {
    let onSessionKey: (String, Date?) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSessionKey: onSessionKey, onCancel: onCancel)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onSessionKey: (String, Date?) -> Void
        let onCancel: () -> Void
        private let targetDomain = "claude.ai"

        init(onSessionKey: @escaping (String, Date?) -> Void, onCancel: @escaping () -> Void) {
            self.onSessionKey = onSessionKey
            self.onCancel = onCancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkForSessionCookie(webView: webView)
        }

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

        private func checkForSessionCookie(webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                for cookie in cookies {
                    if cookie.name == "sessionKey" && cookie.domain.contains(self.targetDomain) {
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
