import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ApplicationPicker: View {
    var add: (String, String) -> Void
    var body: some View {
        Menu {
            ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }, id: \.processIdentifier) { app in
                Button(app.localizedName ?? app.bundleIdentifier!) { add(app.bundleIdentifier!, app.localizedName ?? app.bundleIdentifier!) }
            }
            Divider()
            Button(String(localized: "Browse Applications…")) { browse() }
        } label: { Label(String(localized: "Add App"), systemImage: "plus") }
    }
    private func browse() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.canChooseDirectories = false
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
            add(id, url.deletingPathExtension().lastPathComponent)
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}
