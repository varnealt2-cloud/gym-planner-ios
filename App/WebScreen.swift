import SwiftUI
import WebKit

/// Shows the app's page (index.html in the bundle) full screen.
struct WebScreen: UIViewRepresentable {
    func makeCoordinator() -> WebHost { WebHost() }
    func makeUIView(context: Context) -> WKWebView { context.coordinator.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

final class WebHost: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKURLSchemeHandler {
    /// The page is served from this address instead of a file path, so its storage origin never changes.
    static let scheme = "gymplanner"
    static let home = URL(string: "gymplanner://app/index.html")!
    private static let background = UIColor(red: 0.969, green: 0.957, blue: 1, alpha: 1)

    private(set) var webView: WKWebView!
    private let saved = SavedData.shared
    private let tap = UIImpactFeedbackGenerator(style: .soft)
    private let tick = UISelectionFeedbackGenerator()

    override init() {
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(self, forURLScheme: Self.scheme)
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.add(WeakHandler(self), name: "native")

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.isOpaque = false
        view.backgroundColor = Self.background
        view.scrollView.backgroundColor = Self.background
        // The page lays itself out around the notch and home indicator (env(safe-area-inset-*)).
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.keyboardDismissMode = .interactive
        view.allowsLinkPreview = false
        view.allowsBackForwardNavigationGestures = false
        #if DEBUG
        if #available(iOS 16.4, *) { view.isInspectable = true }
        #endif
        webView = view
        // Test hooks. -forgetWebsiteData stands in for iOS clearing the web view's storage; -resetData starts clean.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetData") { saved.replaceAll([:]); saved.flush() }
        if arguments.contains("-resetData") || arguments.contains("-forgetWebsiteData") {
            WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in self?.loadHome() }
        } else {
            loadHome()
        }
    }

    /// Loads the page. The start-up script is rebuilt each time so it carries the newest saved copy.
    func loadHome() {
        let scripts = webView.configuration.userContentController
        scripts.removeAllUserScripts()
        scripts.addUserScript(WKUserScript(source: Self.startScript(saved: saved.json), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        scripts.addUserScript(WKUserScript(source: Self.readyScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView.load(URLRequest(url: Self.home))
    }

    // MARK: Scripts

    /// Runs before the page's own script: puts back any saved data the web view's storage has lost, then
    /// reports every later change so the copy stays current. Also gives the page a working clipboard.
    static func startScript(saved: String) -> String {
        """
        (function () {
          var saved = \(saved);
          var post = function (message) { try { window.webkit.messageHandlers.native.postMessage(message); } catch (e) {} };
          try {
            var store = window.localStorage;
            var keys = Object.keys(saved), restored = 0;
            // Anything in the saved copy that the web view no longer has was lost, not deleted: deletions made
            // in the app are reported below and removed from the copy too.
            for (var i = 0; i < keys.length; i++) {
              if (store.getItem(keys[i]) === null) { store.setItem(keys[i], saved[keys[i]]); restored++; }
            }
            if (restored) post({ op: "restored", count: restored });
            var all = {};
            for (var j = 0; j < store.length; j++) { var key = store.key(j); all[key] = store.getItem(key); }
            post({ op: "all", values: all });
            var setItem = Storage.prototype.setItem, removeItem = Storage.prototype.removeItem, clear = Storage.prototype.clear;
            Storage.prototype.setItem = function (key, value) {
              setItem.apply(this, arguments);
              if (this === store) post({ op: "set", key: String(key), value: String(value) });
            };
            Storage.prototype.removeItem = function (key) {
              removeItem.apply(this, arguments);
              if (this === store) post({ op: "remove", key: String(key) });
            };
            Storage.prototype.clear = function () {
              clear.apply(this, arguments);
              if (this === store) post({ op: "all", values: {} });
            };
          } catch (e) { post({ op: "log", text: "storage: " + e }); }
          try {
            if (!navigator.clipboard || !navigator.clipboard.writeText) {
              Object.defineProperty(navigator, "clipboard", { configurable: true, value: {
                writeText: function (text) { post({ op: "copy", text: String(text) }); return Promise.resolve(); }
              } });
            }
          } catch (e) {}
        })();
        """
    }

    /// Runs once the page exists: no pinch or double-tap zoom (it is an app, not a document), and a light tap
    /// feel on buttons.
    static let readyScript = """
    (function () {
      var meta = document.querySelector('meta[name="viewport"]');
      if (meta) meta.setAttribute("content", "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover");
      var post = function (message) { try { window.webkit.messageHandlers.native.postMessage(message); } catch (e) {} };
      document.addEventListener("click", function (event) {
        var target = event.target && event.target.closest ? event.target.closest("button, a.btn, summary, label.pill-check, label.sheet-tile") : null;
        if (!target || target.disabled) return;
        post({ op: "haptic", kind: target.closest(".nav, .segments, .week-strip, .qty") ? "tick" : "tap" });
      }, true);
    })();
    """

    // MARK: Messages from the page

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else { return }
        switch op {
        case "set":
            if let key = body["key"] as? String, let value = body["value"] as? String { saved.set(key, value) }
        case "remove":
            if let key = body["key"] as? String { saved.remove(key) }
        case "all":
            if let values = body["values"] as? [String: String] { saved.replaceAll(values) }
        case "copy":
            if let text = body["text"] as? String { UIPasteboard.general.string = text }
        case "haptic":
            if body["kind"] as? String == "tick" { tick.selectionChanged() } else { tap.impactOccurred(intensity: 0.7) }
        default:
            break
        }
    }

    // MARK: Serving the page

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.path == "/index.html" || url.path == "/" || url.path.isEmpty,
              let file = Bundle.main.url(forResource: "index", withExtension: "html"), let data = try? Data(contentsOf: file),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                "Content-Type": "text/html; charset=utf-8", "Content-Length": String(data.count), "Cache-Control": "no-store",
              ]) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == Self.scheme || scheme == "about" || scheme == "blob" || scheme == "data" { decisionHandler(.allow); return }
        // Everything else (exercise videos, sources, Claude) belongs in Safari or its own app.
        if action.targetFrame?.isMainFrame ?? true {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { UIApplication.shared.open(url) }
        return nil
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loadHome() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { retry(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { retry(error) }
    private var retried = false
    private func retry(_ error: Error) {
        guard !retried, (error as NSError).code != NSURLErrorCancelled else { return }
        retried = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.loadHome() }
    }
}

/// WKUserContentController keeps its handlers alive; this keeps that from keeping the host alive too.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
