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
                    consentSheet
                }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Clear Cookies & Re-consent") {
                    Task {
                        await consentManager.clearAllCookies()
                        consentManager.showConsentSheet = true
                    }
                }
            }
        }
        #endif
        .modelContainer(for: [Channel.self, Video.self])
    }

    #if canImport(WebKit)
    private var consentSheet: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("YouTube Consent")
                        .font(.headline)
                    Text("Accept or reject cookies, then click Done.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    Task { await consentManager.finishConsent() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ConsentWebView()
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 600)
    }
    #endif
}
