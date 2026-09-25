import SwiftUI

@main
struct TeslaMIDIApp: App {
    init() {
        // Forza tema scuro coerente con il design Cyberpunk
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = .cyan
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
