import SwiftUI
import AppKit

@main
struct SillViewerApp: App {
    @StateObject private var client = StreamClient()
    @State private var started = false
    var body: some Scene {
        Window("Sill Viewer", id: "viewer") {
            VStack {
                Text(client.status).textSelection(.enabled)
                if client.connected {
                    ViewerPicture(client: client)
                } else {
                    List(client.macs) { mac in
                        Button(mac.name) { client.connect(to: mac) }
                    }
                }
                Text("Preview checkpoint: native input and pairing controls are not yet available.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 640, minHeight: 400)
            .onAppear {
                guard !started else { return }
                started = true
                client.startBrowsing()
            }
        }
    }
}

private struct ViewerPicture: NSViewRepresentable {
    let client: StreamClient
    func makeNSView(context: Context) -> HEVCDisplayView { client.displayView }
    func updateNSView(_ view: HEVCDisplayView, context: Context) {}
}
