import Foundation
import Testing
import UIKit
import WebKit

@MainActor
@Suite(.serialized)
struct WKWebViewScreenTimeReproTests {
    @Test
    func screenTimeEnabled() async throws {
        try await run(screenTimeEnabled: true)
    }

    @Test
    func screenTimeDisabled() async throws {
        try await run(screenTimeEnabled: false)
    }

    private func run(screenTimeEnabled: Bool) async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let identifier = UUID()
        let log = PhaseLog(enabled: screenTimeEnabled)
        log.write("start os=\(ProcessInfo.processInfo.operatingSystemVersionString)")

        for iteration in 1...30 {
            try await loadDocument(
                scene: scene,
                storeIdentifier: identifier,
                screenTimeEnabled: screenTimeEnabled,
                iteration: iteration,
                log: log
            )
        }
        log.write("complete")
    }

    private func loadDocument(
        scene: UIWindowScene,
        storeIdentifier: UUID,
        screenTimeEnabled: Bool,
        iteration: Int,
        log: PhaseLog
    ) async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeIdentifier)
        var originalValue = ObjCBool(false)
        var error: NSError?
        try #require(ReproReadScreenTimeEnabled(configuration.preferences, &originalValue, &error),
                     Comment(rawValue: error?.localizedDescription ?? "Cannot read ScreenTimeEnabled"))
        error = nil
        try #require(ReproSetScreenTimeEnabled(configuration.preferences, screenTimeEnabled, &error),
                     Comment(rawValue: error?.localizedDescription ?? "Cannot set ScreenTimeEnabled"))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        var actualValue = ObjCBool(false)
        error = nil
        try #require(ReproReadScreenTimeEnabled(webView.configuration.preferences, &actualValue, &error))
        try #require(actualValue.boolValue == screenTimeEnabled)
        log.write("iteration=\(iteration) created default=\(originalValue.boolValue) actual=\(actualValue.boolValue)")

        let controller = UIViewController()
        controller.view = webView
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try #require(webView.window != nil)
        log.write("iteration=\(iteration) mounted")
        let load = DocumentLoad(iteration: iteration, log: log)
        defer {
            // WKWebView retains its navigationDelegate weakly.
            withExtendedLifetime(load) {
                webView.navigationDelegate = nil
                webView.stopLoading()
                window.isHidden = true
                webView.removeFromSuperview()
                window.rootViewController = nil
                log.write("iteration=\(iteration) teardown")
            }
        }

        let url = try #require(URL(string: "https://example.com/repro/\(iteration)"))
        webView.navigationDelegate = load
        log.write("iteration=\(iteration) load-begin")
        load.navigation = webView.loadHTMLString(
            "<html><body>ScreenTime reproduction</body></html>",
            baseURL: url
        )

        for try await _ in load.completion.stream {
            log.write("iteration=\(iteration) await-resumed")
            log.write("iteration=\(iteration) javascript-begin")
            let location = try await webView.evaluateJavaScript("window.location.href") as? String
            try #require(location == url.absoluteString)
            log.write("iteration=\(iteration) javascript-complete")
            return
        }
        throw CancellationError()
    }
}

@MainActor
private final class DocumentLoad: NSObject, WKNavigationDelegate {
    var navigation: WKNavigation?
    let completion = AsyncThrowingStream<Void, Error>.makeStream()
    private let iteration: Int
    private let log: PhaseLog

    init(iteration: Int, log: PhaseLog) {
        self.iteration = iteration
        self.log = log
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === self.navigation else { return }
        log.write("iteration=\(iteration) didFinish")
        completion.continuation.yield()
        completion.continuation.finish()
        log.write("iteration=\(iteration) notification-sent")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        guard navigation === self.navigation else { return }
        completion.continuation.finish(throwing: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        guard navigation === self.navigation else { return }
        completion.continuation.finish(throwing: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        completion.continuation.finish(throwing: NSError(
            domain: WKError.errorDomain,
            code: WKError.webContentProcessTerminated.rawValue
        ))
    }
}

@MainActor
private struct PhaseLog {
    let enabled: Bool
    private let start = ProcessInfo.processInfo.systemUptime

    func write(_ message: String) {
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let line = String(format: "[ScreenTimeRepro] pid=%d enabled=%@ elapsed=%.6f %@\n",
                          ProcessInfo.processInfo.processIdentifier,
                          enabled.description, elapsed, message)
        FileHandle.standardOutput.write(Data(line.utf8))
    }
}
