import SwiftUI

@main
struct KbdProbeApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var text = ""

    var body: some View {
        VStack(spacing: 24) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("field")
            Text(text).accessibilityIdentifier("mirror")
        }
        .padding()
    }
}
