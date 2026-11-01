import AppKit
import SwiftUI
import RePrompterCore
import RePrompterUI

@main
struct RePrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        _model = State(initialValue: AppModel.live())
    }

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            AppCommands(model: model, openAbout: { AboutWindow.show() })
        }

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 640, height: 600)
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
