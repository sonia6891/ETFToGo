import SafariServices
import SwiftUI

/// 看即時價: without the viewer's own Fugle key the app shows each trading day's close, so the stock and ETF pages
/// offer the live quote on Yahoo 股市 in an in-app Safari sheet. Hidden once a key is saved (prices then stream here).
struct LiveQuoteButton: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    /// "TWSE" or "TPEx"; Yahoo marks OTC codes .TWO.
    let market: String?
    @State private var showing = false
    var body: some View {
        if !store.liveStatus.hasKey, DataChecks.code(symbol) {
            Button { showing = true } label: { Text("看即時價").font(.caption.bold()) }
                .accessibilityLabel("看即時價")
                .sheet(isPresented: $showing) { SafariSheet(url: Self.url(symbol, market: market)).ignoresSafeArea() }
        }
    }
    static func url(_ symbol: String, market: String?) -> URL {
        URL(string: "https://tw.stock.yahoo.com/quote/\(symbol)\(market == "TPEx" ? ".TWO" : ".TW")")!
    }
}

/// The web version, which anyone can open: shared links point here, and its link preview shows the app icon.
enum WebApp {
    static let site = URL(string: "https://sonia6891.github.io/etftogo-web/")!
    /// A page of the web version, e.g. `stock-2330` or `detail-0050`.
    static func link(_ page: String) -> URL { URL(string: site.absoluteString + "#" + page) ?? site }
}

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
