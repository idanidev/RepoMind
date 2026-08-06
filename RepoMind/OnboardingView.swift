import SwiftUI

/// Shown once, before the token screen.
///
/// The first thing the app used to ask for was a GitHub personal access token, with no explanation
/// of what it was for — which is a lot to ask of someone who has not yet seen the app do anything.
/// These four screens exist to earn that request.
///
/// Each page shows a mock of the actual interface rather than an oversized glyph: the point is to
/// show what the app looks like, and a microphone icon says nothing a microphone icon doesn't.
/// The purple→indigo→blue gradient is the one `LoginView` uses, so arriving at the token screen
/// feels like the next step rather than a different app.
struct OnboardingView: View {
    /// Set when the caller only wants to *look* at the onboarding — replaying it from Settings
    /// must not touch whether the real first run has happened.
    var onFinish: (() -> Void)?

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var page = 0

    private static let pageCount = 4

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                pager
                footer
            }
        }
        .interactiveDismissDisabled()
        // Mac only: a minimum width of 460 on a 402 pt iPhone pushes the header buttons and the
        // primary action off both edges of the screen.
        #if targetEnvironment(macCatalyst)
            .frame(minWidth: 520, minHeight: 620)
        #endif
    }

    // MARK: - Chrome

    private var background: some View {
        ZStack {
            Color(.systemGroupedBackground)
            // A soft wash rather than a full-bleed gradient: the mock cards need to read as
            // interface, and interface on top of a saturated background stops looking real.
            RadialGradient(
                colors: [Color.purple.opacity(0.28), .clear],
                center: .init(x: 0.5, y: 0.18),
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.blue.opacity(0.18), .clear],
                center: .init(x: 0.15, y: 0.75),
                startRadius: 0,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            Text("RepoMind")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button("onboarding_skip") { finish() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .opacity(page < Self.pageCount - 1 ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: page)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private var pager: some View {
        TabView(selection: $page) {
            OnboardingPage(
                title: "onboarding_voice_title", body: "onboarding_voice_body",
                illustration: { VoiceMock() }
            ).tag(0)

            OnboardingPage(
                title: "onboarding_board_title", body: "onboarding_board_body",
                illustration: { BoardMock() }
            ).tag(1)

            OnboardingPage(
                title: "onboarding_issues_title", body: "onboarding_issues_body",
                illustration: { IssueMock() }
            ).tag(2)

            OnboardingPage(
                title: "onboarding_agent_title", body: "onboarding_agent_body",
                illustration: { AgentMock() }
            ).tag(3)
        }
        #if !targetEnvironment(macCatalyst)
            .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }

    private var footer: some View {
        VStack(spacing: 20) {
            // Hand-rolled rather than the system dots: those render in a tint that disappears
            // against this background, and the count is worth seeing.
            HStack(spacing: 8) {
                ForEach(0..<Self.pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color.purple : Color.secondary.opacity(0.3))
                        .frame(width: index == page ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: page)
                }
            }

            Button {
                if page < Self.pageCount - 1 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page < Self.pageCount - 1 ? "onboarding_next" : "onboarding_start")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
    }

    private func finish() {
        if let onFinish {
            onFinish()
        } else {
            hasSeenOnboarding = true
        }
    }
}

// MARK: - Page scaffold

private struct OnboardingPage<Illustration: View>: View {
    let title: LocalizedStringKey
    let body_: LocalizedStringKey
    @ViewBuilder let illustration: () -> Illustration

    init(
        title: LocalizedStringKey,
        body: LocalizedStringKey,
        @ViewBuilder illustration: @escaping () -> Illustration
    ) {
        self.title = title
        self.body_ = body
        self.illustration = illustration
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 12)

            illustration()
                .frame(maxWidth: 320)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)

            VStack(spacing: 10) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(body_)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 12)
        }
    }
}

/// The surface every mock is drawn on, so they read as one interface across the four pages.
private struct MockCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

// MARK: - Page 1: voice capture

private struct VoiceMock: View {
    @State private var animating = false

    private let heights: [CGFloat] = [10, 22, 14, 32, 18, 40, 26, 34, 16, 28, 12, 20]

    var body: some View {
        MockCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .opacity(animating ? 1 : 0.3)
                    Text("onboarding_mock_recording")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text("onboarding_mock_transcript")
                    .font(.system(size: 17, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 4) {
                    ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .indigo],
                                    startPoint: .top, endPoint: .bottom)
                            )
                            .frame(width: 4, height: animating ? height : height * 0.35)
                            .animation(
                                .easeInOut(duration: 0.5)
                                    .repeatForever()
                                    .delay(Double(index) * 0.06),
                                value: animating
                            )
                    }
                }
                .frame(height: 44, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { animating = true }
    }
}

// MARK: - Page 2: the board

private struct BoardMock: View {
    var body: some View {
        MockCard {
            HStack(alignment: .top, spacing: 12) {
                column(
                    name: "onboarding_mock_col_todo", tint: .purple, count: 2,
                    tasks: ["onboarding_mock_task_1", "onboarding_mock_task_2"])
                column(
                    name: "onboarding_mock_col_done", tint: .green, count: 1,
                    tasks: ["onboarding_mock_task_3"], done: true)
            }
        }
    }

    private func column(
        name: LocalizedStringKey, tint: Color, count: Int,
        tasks: [LocalizedStringKey], done: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint, in: RoundedRectangle(cornerRadius: 8))

            ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(done ? .green : .secondary)
                    Text(task)
                        .font(.caption)
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(9)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Page 3: tasks become issues

private struct IssueMock: View {
    var body: some View {
        MockCard {
            VStack(spacing: 10) {
                row {
                    Image(systemName: "circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("onboarding_mock_task_1")
                        .font(.caption)
                    Spacer(minLength: 0)
                }

                Image(systemName: "arrow.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)

                row {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("onboarding_mock_task_1")
                        .font(.caption)
                    Spacer(minLength: 0)
                    Text("#142")
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }

                Label("onboarding_mock_issue_hint", systemImage: "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8, content: content)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Page 4: the agent reads them

private struct AgentMock: View {
    var body: some View {
        MockCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { dot in
                        Circle().fill(dot.opacity(0.8)).frame(width: 8, height: 8)
                    }
                    Spacer()
                    Text("claude code")
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)

                terminalLine("onboarding_mock_agent_prompt", tint: .purple, mono: true)
                terminalLine("onboarding_mock_agent_reading", tint: .secondary, mono: true)
                terminalLine("onboarding_mock_agent_task", tint: .primary, mono: false)
                terminalLine("onboarding_mock_agent_done", tint: .green, mono: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func terminalLine(_ key: LocalizedStringKey, tint: Color, mono: Bool) -> some View {
        Text(key)
            .font(.caption2)
            .monospaced(mono)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    OnboardingView()
}
