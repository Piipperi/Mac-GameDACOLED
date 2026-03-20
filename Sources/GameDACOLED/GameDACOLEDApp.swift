import AppKit
import AppIntents
import SwiftUI

@main
struct GameDACOLEDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    init() {
        GameDACShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        MenuBarExtra("GameDAC OLED", systemImage: "play.display") {
            MenuBarView {
                appDelegate.showControlWindow()
            }
                .environmentObject(appModel)
                .onAppear {
                    appDelegate.install(appModel: appModel)
                }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var appModel: AppModel?
    private var controlWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func install(appModel: AppModel) {
        self.appModel = appModel
    }

    @MainActor
    @objc func showControlWindow() {
        guard let appModel else { return }

        if let controlWindow {
            controlWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = ContentView()
            .environmentObject(appModel)
            .frame(minWidth: 760, minHeight: 620)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "GameDAC OLED Controller"
        window.setContentSize(NSSize(width: 760, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.delegate = self
        controlWindow = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == controlWindow else {
            return
        }
        controlWindow = nil
    }
}
