import AppTrackingTransparency
import GoogleMobileAds
import SwiftUI
import UIKit

// MARK: - AdMob
//
// TODO: Replace `bannerAdUnitID` and `GADApplicationIdentifier` in
// Config/AppInfo.plist with the AdMob app ID and banner unit created under
// publisher ca-app-pub-8874506793712009.
// The IDs below are Google's public test IDs. They never bill that publisher.

enum AdMobConfig {
    static let publisherID = "ca-app-pub-8874506793712009"
    /// Google's iOS banner test unit (adaptive banners included).
    static let bannerAdUnitID = "ca-app-pub-3940256099942544/2435281174"
    /// Caps the inline adaptive banner so it stays a short strip in a list.
    static let maxBannerHeight: CGFloat = 60
}

@MainActor
final class AdMobStartup: ObservableObject {
    static let shared = AdMobStartup()

    @Published private(set) var canLoadAds = false
    private var startup: Task<Void, Never>?

    /// Asks for tracking permission, then starts the ads SDK. Safe to call more than once.
    func prepare() {
        guard startup == nil else { return }
        startup = Task { await start() }
    }

    private func start() async {
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            try? await Task.sleep(nanoseconds: 400_000_000)
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            MobileAds.shared.start { _ in
                continuation.resume()
            }
        }
        canLoadAds = true
    }
}

/// Small inline adaptive banner for the bottom of a main list. Hidden for MD Shift+ members.
struct AdBannerView: View {
    var placement: String = "dashboard"
    @ObservedObject private var plus = PlusMembershipStore.shared
    @ObservedObject private var ads = AdMobStartup.shared

    var body: some View {
        Group {
            if plus.showsAds, ads.canLoadAds {
                AdaptiveAdBanner(placement: placement)
            }
        }
        .task {
            await plus.refresh()
            if plus.showsAds {
                ads.prepare()
            }
        }
    }
}

private struct AdaptiveAdBanner: View {
    let placement: String
    @State private var height: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if height > 1 {
                Text("Advertisement")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .accessibilityHidden(true)
            }
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: max(height, 1))
                .overlay {
                    GeometryReader { proxy in
                        let measured = proxy.size.width
                        if measured > 1 {
                            BannerHost(width: measured, placement: placement) { loaded in
                                if abs(loaded - height) > 0.5 {
                                    height = loaded
                                }
                            }
                        }
                    }
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Advertisement")
    }
}

private struct BannerHost: UIViewRepresentable {
    let width: CGFloat
    let placement: String
    var onHeight: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeight: onHeight)
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: Self.adSize(width: width))
        banner.adUnitID = AdMobConfig.bannerAdUnitID
        banner.rootViewController = context.coordinator.presenter()
        banner.delegate = context.coordinator
        banner.load(Self.request(placement: placement))
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        let size = Self.adSize(width: width)
        if !isAdSizeEqualToSize(size1: banner.adSize, size2: size) {
            banner.adSize = size
        }
        banner.rootViewController = context.coordinator.presenter()
    }

    private static func adSize(width: CGFloat) -> AdSize {
        inlineAdaptiveBanner(width: max(width, 1), maxHeight: AdMobConfig.maxBannerHeight)
    }

    private static func request(placement: String) -> Request {
        let request = Request()
        request.customTargeting = ["placement": placement]
        return request
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        let onHeight: (CGFloat) -> Void

        init(onHeight: @escaping (CGFloat) -> Void) {
            self.onHeight = onHeight
        }

        func presenter() -> UIViewController? {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
            return window?.rootViewController
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            let loaded = bannerView.adSize.size.height
            onHeight(loaded > 0 ? min(loaded, AdMobConfig.maxBannerHeight) : 0)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            onHeight(0)
        }
    }
}
