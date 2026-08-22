import SwiftUI
import UIKit
import WebKit

// MARK: - Ad Banner
// Real ads: WKWebView loads mdshift.net/ads/banner.html (AdSense when configured,
// otherwise live sponsor click-outs). Hidden for MD Shift+ members.

struct AdBannerView: View {
    var placement: String = "dashboard"
    @ObservedObject private var plus = PlusMembershipStore.shared

    var body: some View {
        Group {
            if plus.showsAds {
                AdWebBanner(placement: placement)
                    .frame(height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Brand.border, lineWidth: 1)
                    }
                    .accessibilityLabel("Advertisement")
            }
        }
        .task { await plus.refresh() }
    }
}

private struct AdWebBanner: UIViewRepresentable {
    let placement: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.isOpaque = false
        web.backgroundColor = .clear
        web.navigationDelegate = context.coordinator
        load(into: web)
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // placement changes are rare; reload if needed
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func load(into web: WKWebView) {
        let base = SupabaseConfig.websiteBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(base)/ads/banner.html?placement=\(placement.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? placement)"
        if let url = URL(string: urlString) {
            web.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
