import SwiftUI
import WebKit

/// Microsoft sign-in through Zammad's own Microsoft 365 login, the same way the web app does it.
/// The browser view starts with the app's web session and hands the signed-in cookies back.
struct MicrosoftSignInView: UIViewRepresentable {
    let client: ZammadClient
    let web: WebSession
    let fingerprint: String
    let onSignedIn: () -> Void

    /// Zammad only starts the Microsoft login on a POST that carries the session's CSRF token.
    static func startPage(csrf: String, fingerprint: String, server: URL) -> String {
        func escape(_ s: String) -> String {
            s.replacing("&", with: "&amp;").replacing("\"", with: "&quot;").replacing("<", with: "&lt;")
        }
        let action = escape(server.appending(path: "auth/microsoft_office365").absoluteString)
        return """
        <html><body onload="document.forms[0].submit()"><form method="post" action="\(action)">
        <input type="hidden" name="authenticity_token" value="\(escape(csrf))">
        <input type="hidden" name="fingerprint" value="\(escape(fingerprint))">
        </form></body></html>
        """
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        let store = config.websiteDataStore.httpCookieStore
        Task {
            for cookie in web.cookies { await store.setCookie(cookie) }
            view.loadHTMLString(Self.startPage(csrf: web.csrf ?? "", fingerprint: fingerprint, server: client.baseURL),
                                baseURL: client.baseURL)
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: MicrosoftSignInView
        private var done = false

        init(parent: MicrosoftSignInView) { self.parent = parent }

        /// Back on the Zammad server after Microsoft: take over the cookies and check whether the session is signed in.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let host = parent.client.baseURL.host()
            guard !done, webView.url?.host() == host else { return }
            Task {
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                parent.web.merge(cookies.filter { host?.hasSuffix($0.domain.trimmingPrefix(".")) == true })
                if !done, (try? await parent.client.me()) != nil {
                    done = true
                    parent.onSignedIn()
                }
            }
        }
    }
}
