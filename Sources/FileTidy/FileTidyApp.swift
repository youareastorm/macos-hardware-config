import SwiftUI

@main
struct FileTidyApp: App {
    @StateObject private var viewModel = OrganizerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowResizability(.contentSize)
    }
}
