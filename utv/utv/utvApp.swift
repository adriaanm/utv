import SwiftUI
import SwiftData

#if canImport(WebKit)
import WebKit
#endif

@main
struct utvApp: App {
    #if canImport(WebKit)
    @State private var consentManager = ConsentManager.shared
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if canImport(WebKit)
                .task {
                    await consentManager.ensureConsent()
                }
                .sheet(isPresented: $consentManager.showConsentSheet) {
                    VStack {
                        Text("YouTube requires consent")
                            .font(.headline)
                            .padding(.top)
                        Text("Please accept or reject cookies to continue.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ConsentWebView()
                            .frame(minWidth: 500, minHeight: 400)
                    }
                    .padding()
                }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        #endif
        .modelContainer(for: [Channel.self, Video.self])
    }
}
