// dwcard — shows a local HTML file in an always-on-top, borderless-ish panel.
// Usage: dwcard <html-file> [window-title]
// Loads ONLY the given local file. The only network action is opening an
// http(s) link the user clicks (e.g. "Open run") in their default browser.
import Cocoa
import WebKit

final class Delegate: NSObject, WKNavigationDelegate, NSWindowDelegate {
    weak var win: NSWindow?

    // Resize the window to fit the card's content (no scrolling), capped to screen.
    func fit(_ webView: WKWebView) {
        webView.evaluateJavaScript("(function(){var c=document.querySelector('.card');return c?c.offsetHeight:document.body.scrollHeight;})()") { [weak self] result, _ in
            guard let win = self?.win,
                  let h = (result as? NSNumber)?.doubleValue, h > 0 else { return }
            let want = min(h + 40, (NSScreen.main?.visibleFrame.height ?? 900) - 60)
            let curW = win.contentView?.frame.width ?? 440
            win.setContentSize(NSSize(width: curW, height: want))
            win.center()
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { fit(webView) }

    // Open real links (Open run) in the default browser; keep the panel local.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" {
                NSWorkspace.shared.open(url)          // Open run → default browser
                decisionHandler(.cancel)
                return
            }
            if scheme == "dwcard" {
                switch url.host {
                case "pick", "input":                 // picker choice / typed value → print, exit
                    let val = String(url.path.dropFirst())   // strip leading "/", keep the rest
                    FileHandle.standardOutput.write(Data((val + "\n").utf8))
                    NSApp.terminate(nil)
                case "kill":                          // stop a watcher, remove its row, keep window
                    let s = url.path.replacingOccurrences(of: "/", with: "")
                    if let n = Int32(s) { kill(n, SIGTERM) }
                    webView.evaluateJavaScript("var e=document.querySelector('[data-pid=\"\(s)\"]');if(e)e.remove();") { [weak self] _, _ in
                        if let self = self { self.fit(webView) }
                    }
                default:                              // close / cancel → exit
                    NSApp.terminate(nil)
                }
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: dwcard <html-file> [title]\n".utf8))
    exit(1)
}
let fileURL = URL(fileURLWithPath: args[1])
let title = args.count >= 3 ? args[2] : "DeployWatcher"
let winW = args.count >= 4 ? (Double(args[3]) ?? 440) : 440
let winH = args.count >= 5 ? (Double(args[4]) ?? 640) : 640

let app = NSApplication.shared
app.setActivationPolicy(.accessory)          // no Dock icon
let delegate = Delegate()

let rect = NSRect(x: 0, y: 0, width: winW, height: winH)
let window = NSWindow(contentRect: rect,
                      styleMask: [.titled, .closable],
                      backing: .buffered, defer: false)
window.title = title
window.level = .floating                      // stays above normal windows
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
window.isReleasedWhenClosed = false
window.delegate = delegate
delegate.win = window
window.center()

let web = WKWebView(frame: rect)
web.navigationDelegate = delegate
web.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
window.contentView = web

// Minimal Edit menu so Cmd-C/V/X/A reach the focused field (needed because an
// accessory app otherwise routes no standard editing shortcuts).
let mainMenu = NSMenu()
let editTop = NSMenuItem()
mainMenu.addItem(editTop)
let editMenu = NSMenu(title: "Edit")
editTop.submenu = editMenu
editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
app.mainMenu = mainMenu

window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()
