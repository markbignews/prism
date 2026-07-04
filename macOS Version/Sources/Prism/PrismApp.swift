import SwiftUI

@main
struct PrismApp: App {
    @StateObject private var chatStore = ChatStore()
    @StateObject private var settings = AppSettings()
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chatStore)
                .environmentObject(settings)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    chatStore.bootstrapIfNeeded(language: settings.language)
                    // Show onboarding on first launch (never seen) when no API key is set.
                    // Brief delay so the window is fully laid out first.
                    if !settings.onboardingCompleted
                        && settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        try? await Task.sleep(for: .milliseconds(400))
                        showOnboarding = true
                    }
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView()
                        .environmentObject(settings)
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L10n.text(.newConversation, settings.language)) {
                    chatStore.createConversation(language: settings.language)
                }
                .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .frame(width: 520)
        }
    }
}
