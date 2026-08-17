import SwiftUI

// MARK: - Onboarding View

/// A multi-page onboarding flow following Apple's Human Interface Guidelines:
/// - One concept per page
/// - Progressive disclosure
/// - Clear call-to-action
/// - Skip available on first page, Back on subsequent pages
///
/// Pages:
/// 1. Welcome — app identity and value proposition
/// 2. Purpose — what Prism does (not a therapist, a mirror)
/// 3. Features — core capabilities with SF Symbol cards
/// 4. UI Tour — sidebar, chat, input, toolbar walkthrough
/// 5. API Key Setup — guided DeepSeek API configuration
/// 6. Conversation Mode — choose rational/balanced/warm
/// 7. iCloud Storage — cloud sync or local storage
/// 8. Data & Privacy — where everything is stored
struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage = 0
    @State private var apiKeyInput = ""
    @State private var apiKeySaved = false

    /// API key validation state (Tauri parity: onboarding validates the key
    /// against the provider's /models endpoint before continuing).
    private enum ValidationState: Equatable {
        case idle
        case checking
        case success
        case failure(String)
    }

    @State private var validationState: ValidationState = .idle

    private let totalPages = 8

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Page content — scrolls when too tall, bottom bar stays pinned
            GeometryReader { geo in
                ScrollView(.vertical) {
                    currentPageView
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
            }

            // Bottom bar: always fixed at the bottom, never shifts
            bottomBar
        }
        .frame(width: 600, height: 520)
        .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            settings.dataPath = url.path
        }
        .onAppear {
            apiKeyInput = settings.apiKey
        }
    }

    @State private var showFolderImporter = false

    /// Marks onboarding as completed so it won't show again, then dismisses.
    private func finishOnboarding() {
        settings.onboardingCompleted = true
        dismiss()
    }

    @ViewBuilder
    private var currentPageView: some View {
        switch currentPage {
        case 0: welcomePage
        case 1: purposePage
        case 2: featuresPage
        case 3: uiTourPage
        case 4: apiKeyPage
        case 5: conversationModePage
        case 6: iCloudPage
        case 7: dataPage
        default: welcomePage
        }
    }

    private func goToNextPage() {
        guard currentPage < totalPages - 1 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPage += 1
        }
    }

    private func goToPreviousPage() {
        guard currentPage > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPage -= 1
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Left: skip on first page, back on all others
            if currentPage == 0 {
                Button(L10n.text(.onboardingSkip, settings.language)) {
                    finishOnboarding()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.body)
            } else {
                Button(L10n.text(.onboardingBack, settings.language)) {
                    goToPreviousPage()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.body)
            }

            Spacer()

            // Center: page indicator dots
            HStack(spacing: 6) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityLabel(
                String(format: L10n.text(.onboardingPageIndicator, settings.language),
                       currentPage + 1, totalPages)
            )

            Spacer()

            // Right: continue, save-key, or get-started
            if currentPage == totalPages - 1 {
                Button(L10n.text(.onboardingGetStarted, settings.language)) {
                    if !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        settings.apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .font(.body.weight(.medium))
            } else if currentPage == 4 {
                // API Key page: dedicated save button
                Button {
                    settings.apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    apiKeySaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        goToNextPage()
                    }
                } label: {
                    Label(
                        apiKeySaved ? "✓" : L10n.text(.save, settings.language),
                        systemImage: apiKeySaved ? "checkmark.circle.fill" : "key.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .font(.body.weight(.medium))
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiKeySaved)
            } else {
                Button(L10n.text(.onboardingContinue, settings.language)) {
                    goToNextPage()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .font(.body.weight(.medium))
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Page 1: Welcome

extension OnboardingView {
    private var welcomePage: some View {
        VStack(spacing: 24) {

            AppIconImage()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text(L10n.text(.onboardingWelcomeTitle, settings.language))
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text(L10n.text(.modePrism, settings.language))
                .font(.title3.weight(.medium))
                .foregroundStyle(.blue)

            Text(L10n.text(.onboardingWelcomeBody, settings.language))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .lineSpacing(4)

        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
    }
}

// MARK: - Page 2: Purpose

extension OnboardingView {
    private var purposePage: some View {
        VStack(spacing: 24) {

            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.blue)

            Text(L10n.text(.onboardingPurposeTitle, settings.language))
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text(L10n.text(.onboardingPurposeBody, settings.language))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .lineSpacing(4)

            VStack(alignment: .leading, spacing: 14) {
                purposeRow(icon: "text.alignleft", color: .blue, text: purposeRow1)
                purposeRow(icon: "eye", color: .orange, text: purposeRow2)
                purposeRow(icon: "lightbulb", color: .yellow, text: purposeRow3)
            }
            .padding(.horizontal, 20)

        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
    }

    private func purposeRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }

    private var purposeRow1: String {
        switch settings.language {
        case .traditionalChinese:
            return "不是心理醫生，不做診斷、不貼標籤"
        case .english:
            return "Not a therapist — does not diagnose or label"
        default:
            return "不是心理医生，不做诊断、不贴标签"
        }
    }

    private var purposeRow2: String {
        switch settings.language {
        case .traditionalChinese:
            return "幫你拆分事實與解釋，看清盲點"
        case .english:
            return "Separates facts from interpretations, reveals blind spots"
        default:
            return "帮你拆分事实与解释，看清盲点"
        }
    }

    private var purposeRow3: String {
        switch settings.language {
        case .traditionalChinese:
            return "最終目標：幫你走到不再需要打開稜鏡的那一天"
        case .english:
            return "The goal: help you reach the day you no longer need to open Prism"
        default:
            return "最终目标：帮你走到不再需要打开棱镜的那一天"
        }
    }
}

// MARK: - Page 3: Features

extension OnboardingView {
    private var featuresPage: some View {
        VStack(spacing: 24) {

            Image(systemName: "square.grid.2x2")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.blue)

            Text(L10n.text(.onboardingFeaturesTitle, settings.language))
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text(L10n.text(.onboardingFeaturesBody, settings.language))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ], spacing: 14) {
                featureCard(
                    icon: "list.bullet.rectangle", color: .blue,
                    title: L10n.text(.featureNarrativeTitle, settings.language),
                    desc: L10n.text(.featureNarrativeDesc, settings.language)
                )
                featureCard(
                    icon: "eye.trianglebadge.exclamationmark", color: .orange,
                    title: L10n.text(.featureBlindspotTitle, settings.language),
                    desc: L10n.text(.featureBlindspotDesc, settings.language)
                )
                featureCard(
                    icon: "rectangle.3.group", color: .green,
                    title: L10n.text(.featurePerspectiveTitle, settings.language),
                    desc: L10n.text(.featurePerspectiveDesc, settings.language)
                )
                featureCard(
                    icon: "bookmark", color: .purple,
                    title: L10n.text(.featureChapterTitle, settings.language),
                    desc: L10n.text(.featureChapterDesc, settings.language)
                )
            }
            .frame(maxWidth: 480)

        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
    }

    private func featureCard(icon: String, color: Color, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }
}

// MARK: - Page 4: UI Tour

extension OnboardingView {
    private var uiTourPage: some View {
        VStack(spacing: 24) {

            Image(systemName: "rectangle.3.group")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.blue)

            Text(L10n.text(.onboardingUITourTitle, settings.language))
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text(L10n.text(.onboardingUITourBody, settings.language))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            VStack(spacing: 10) {
                uiTourRow(
                    icon: "sidebar.left", color: .blue,
                    title: L10n.text(.uiSidebarTitle, settings.language),
                    desc: L10n.text(.uiSidebarDesc, settings.language)
                )
                uiTourRow(
                    icon: "bubble.left.and.bubble.right", color: .blue,
                    title: L10n.text(.uiChatTitle, settings.language),
                    desc: L10n.text(.uiChatDesc, settings.language)
                )
                uiTourRow(
                    icon: "keyboard", color: .green,
                    title: L10n.text(.uiInputTitle, settings.language),
                    desc: L10n.text(.uiInputDesc, settings.language)
                )
                uiTourRow(
                    icon: "slider.horizontal.3", color: .orange,
                    title: L10n.text(.uiToolbarTitle, settings.language),
                    desc: L10n.text(.uiToolbarDesc, settings.language)
                )
            }
            .frame(maxWidth: 480)

        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
    }

    private func uiTourRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }
}

// MARK: - Page 5: API Key Setup

extension OnboardingView {
    private var apiKeyPage: some View {
        VStack(spacing: 24) {

            Image(systemName: "key.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.blue)

            Text(L10n.text(.onboardingAPIKeyTitle, settings.language))
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text(L10n.text(.onboardingAPIKeyBody, settings.language))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .lineSpacing(4)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text(.apiKey, settings.language))
                    .font(.subheadline.weight(.semibold))

                SecureField("sk-...", text: $apiKeyInput)
                    .textFieldStyle(.plain)
                    .font(.body.monospaced())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.quaternary.opacity(0.3))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(apiKeySaved ? Color.green.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .onSubmit {
                        saveAndAdvance()
                    }

                // Online validation (Tauri parity) — non-blocking.
                HStack(spacing: 8) {
                    Button {
                        validateAPIKey()
                    } label: {
                        if validationState == .checking {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(L10n.text(.validating, settings.language))
                            }
                        } else {
                            Label(L10n.text(.validate, settings.language), systemImage: "checkmark.seal")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || validationState == .checking)

                    switch validationState {
                    case .success:
                        Label(L10n.text(.validationSuccess, settings.language), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    case .failure(let message):
                        VStack(alignment: .leading, spacing: 2) {
                            Label(L10n.text(.validationFailed, settings.language), systemImage: "xmark.circle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.red)
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    case .idle, .checking:
                        EmptyView()
                    }
                }
            }
            .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(apiKeyHelpTitle)
                        .font(.caption.weight(.semibold))
                }
                Text(apiKeyHelpBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            .padding(12)
            .frame(maxWidth: 400, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.blue.opacity(0.08))
            )

            Text(apiKeyFooterNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
    }

    private func saveAndAdvance() {
        guard !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        settings.apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKeySaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            goToNextPage()
        }
    }

    /// Validate the entered key online. Failure does not block the flow —
    /// the user can continue and fix it later in Settings (Tauri parity).
    private func validateAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, validationState != .checking else { return }
        validationState = .checking
        Task {
            let client = DeepSeekClient(
                apiKey: key,
                baseURL: settings.baseURL,
                model: settings.model,
                parameters: settings.parameters,
                language: settings.language
            )
            do {
                try await client.validateAPIKey(apiKey: key, baseURL: settings.baseURL)
                if !Task.isCancelled {
                    validationState = .success
                }
            } catch {
                if !Task.isCancelled {
                    validationState = .failure(error.localizedDescription)
                }
            }
        }
    }

    private var apiKeyHelpTitle: String {
        switch settings.language {
        case .traditionalChinese:
            return "如何獲取 API Key？"
        case .english:
            return "How to get an API Key?"
        default:
            return "如何获取 API Key？"
        }
    }

    private var apiKeyHelpBody: String {
        switch settings.language {
        case .traditionalChinese:
            return "前往 platform.deepseek.com 註冊帳號，在「API Keys」頁面建立一個新的 Key。DeepSeek 新用戶通常會有免費額度。"
        case .english:
            return "Go to platform.deepseek.com, create an account, and generate a new API key from the «API Keys» page. New DeepSeek users typically receive free credits."
        default:
            return "前往 platform.deepseek.com 注册账号，在「API Keys」页面创建一个新的 Key。DeepSeek 新用户通常会有免费额度。"
        }
    }

    private var apiKeyFooterNote: String {
        switch settings.language {
        case .traditionalChinese:
            return "你也可以稍後在「設定 → DeepSeek」中配置 API Key、Base URL 和模型參數。"
        case .english:
            return "You can also configure the API key, base URL, and model parameters later in Settings → DeepSeek."
        default:
            return "你也可以稍后在「设置 → DeepSeek」中配置 API Key、Base URL 和模型参数。"
        }
    }
}

// MARK: - Page 6: Conversation Mode

extension OnboardingView {
    private var conversationModePage: some View {
        VStack(spacing: 24) {
            AppIconImage()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 8) {
                Text(L10n.text(.onboardingModeTitle, settings.language))
                    .font(.title.weight(.semibold))
                Text(L10n.text(.onboardingModeBody, settings.language))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Mode cards
            VStack(spacing: 12) {
                modeCard(
                    icon: "snowflake",
                    title: L10n.text(.modeRational, settings.language),
                    description: L10n.text(.modeRationalDesc, settings.language),
                    mode: .rational
                )
                modeCard(
                    icon: "equal",
                    title: L10n.text(.modeBalanced, settings.language),
                    description: L10n.text(.modeBalancedDesc, settings.language),
                    mode: .balanced
                )
                modeCard(
                    icon: "heart",
                    title: L10n.text(.modeWarm, settings.language),
                    description: L10n.text(.modeWarmDesc, settings.language),
                    mode: .warm
                )
            }
            .padding(.horizontal, 48)

            // Response length picker
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text(.responseLength, settings.language))
                    .font(.subheadline.weight(.semibold))
                Picker("", selection: $settings.responseLength) {
                    Text(L10n.text(.modeBrief, settings.language)).tag(ResponseLength.brief)
                    Text(L10n.text(.modeStandard, settings.language)).tag(ResponseLength.standard)
                    Text(L10n.text(.modeDetailed, settings.language)).tag(ResponseLength.detailed)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 32)
    }

    private func modeCard(icon: String, title: String, description: String, mode: ConversationMode) -> some View {
        Button {
            settings.conversationMode = mode
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if settings.conversationMode == mode {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 18))
                }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(settings.conversationMode == mode
                    ? Color.blue.opacity(0.08)
                    : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(settings.conversationMode == mode
                    ? Color.blue.opacity(0.3)
                    : Color.secondary.opacity(0.1),
                    lineWidth: 1)
        )
    }
}

// MARK: - Page 7: iCloud Storage

extension OnboardingView {
    private var iCloudPage: some View {
        VStack(spacing: 28) {
            Image(systemName: "icloud.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 10) {
                Text(L10n.text(.useiCloud, settings.language))
                    .font(.title.weight(.semibold))
                Text(L10n.text(.iCloudActive, settings.language))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Toggle(L10n.text(.useiCloud, settings.language), isOn: $settings.useiCloud)
                .toggleStyle(.switch)
                .font(.headline)
                .padding(.horizontal, 48)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(settings.dataPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.quaternary.opacity(0.5))
                )

                if !settings.useiCloud {
                    Button(L10n.text(.choose, settings.language)) {
                        showFolderImporter = true
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Page 8: Data & Privacy

extension OnboardingView {
    private var dataPage: some View {
        VStack(spacing: 24) {

            Image(systemName: "lock.shield")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.blue)

            Text(L10n.text(.onboardingDataTitle, settings.language))
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text(L10n.text(.onboardingDataBody, settings.language))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .lineSpacing(4)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ], spacing: 14) {
                dataCard(
                    icon: "doc.text", color: .blue,
                    title: L10n.text(.dataStorageTitle, settings.language),
                    desc: L10n.text(.dataStorageDesc, settings.language)
                )
                dataCard(
                    icon: "gearshape", color: .gray,
                    title: L10n.text(.dataConfigTitle, settings.language),
                    desc: L10n.text(.dataConfigDesc, settings.language)
                )
                dataCard(
                    icon: "hand.raised", color: .green,
                    title: L10n.text(.dataPrivacyTitle, settings.language),
                    desc: L10n.text(.dataPrivacyDesc, settings.language)
                )
                dataCard(
                    icon: "archivebox", color: .orange,
                    title: L10n.text(.dataArchiveTitle, settings.language),
                    desc: L10n.text(.dataArchiveDesc, settings.language)
                )
            }
            .frame(maxWidth: 480)

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(settings.dataPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )

        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
    }

    private func dataCard(icon: String, color: Color, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .environmentObject(AppSettings())
    }
}
#endif
