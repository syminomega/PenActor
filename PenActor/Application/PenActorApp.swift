import SwiftUI

@main
struct PenActorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra {
            StatusMenu(monitor: delegate.monitor) { delegate.preferences.open($0) }
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityLabel("PenActor")
        }.menuBarExtraStyle(.menu)
    }
}
