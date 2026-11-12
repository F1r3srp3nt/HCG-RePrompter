import AppKit
import SwiftUI
import RePrompterCore
import RePrompterUI

@main
struct RePrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        let model = AppModel.live()
        _model = State(initialValue: model)
        // The open prompt is autosaved shortly after each edit; flush it when
        // the app quits so the very last keystrokes are kept too.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { model.flushSession() }
        }
    }

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            RootView()
                .environment(model)
                // Every view inside fits this size: the workspace adapts its
                // layout instead of requiring a minimum width.
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            AppCommands(model: model, openAbout: { AboutWindow.show() })
        }

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 600, height: 480)
        }
    }
}

/// Native window behaviour for an app launched as a plain executable or bundle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // When running unbundled (swift run / Xcode), use the HCG icon in the Dock.
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") == nil, let icon = BrandAssets.appIcon {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// A single, reusable About window.
@MainActor
enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: AboutView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "About \(AppInfo.name)"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.appearance = NSAppearance(named: .darkAqua)
            newWindow.center()
            window = newWindow
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
