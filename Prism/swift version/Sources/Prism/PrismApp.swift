import SwiftUI

extension Notification.Name {
    /// Allows the app menu command to open the same memory panel as the toolbar.
    static let openMemoryPanel = Notification.Name("Prism.openMemoryPanel")
}

@main
struct PrismApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var chatStore = ChatStore()
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chatStore)
                .environmentObject(settings)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    settings.canChangeStorage = { !chatStore.isSending && !chatStore.isSummarizing }
                    // ChatStore is initialized before AppSettings. Reconcile it
                    // with any storage path selected while settings were loaded.
                    chatStore.reloadStorage(from: settings)
                    chatStore.bootstrapIfNeeded(language: settings.language)
                    if !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task { await settings.refreshProviderBalance() }
                    }
                    // Show onboarding on first launch (never seen) when no API key is set.
                    // Brief delay so the window is fully laid out first.
                    if !settings.onboardingCompleted
                        && settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        try? await Task.sleep(for: .milliseconds(400))
                        showOnboarding = true
                    }
                }
                .onChange(of: settings.dataPath) { oldPath, newPath in
                    if oldPath != newPath {
                        chatStore.reloadStorage(from: settings)
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

                Button(L10n.text(.memory, settings.language)) {
                    NotificationCenter.default.post(name: .openMemoryPanel, object: nil)
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(chatStore)
                .frame(width: 520)
        }
    }
}
