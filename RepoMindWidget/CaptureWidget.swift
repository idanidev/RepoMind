import SwiftUI
import WidgetKit

// MARK: - Widget

/// A button on the Home Screen and the Lock Screen: tapping it opens RepoMind on the dictation
/// sheet with the microphone already on. A widget cannot record audio itself, so what it does is
/// get the developer from the phone's home to "say the app and the task" in one tap.
///
/// It holds no data (no app group, nothing to refresh), which is also why it needs no entitlement.
struct CaptureWidget: Widget {
    let kind = "RepoMindCaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaptureProvider()) { _ in
            CaptureWidgetView()
                .widgetURL(CaptureLink.url)
                .containerBackground(for: .widget) { CaptureStyle.background }
        }
        .configurationDisplayName("widget_name")
        .description("widget_description")
        .supportedFamilies([
            .systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

/// `repomind://capture`, the link the app answers by opening the dictation sheet.
enum CaptureLink {
    static let url: URL = {
        var components = URLComponents()
        components.scheme = "repomind"
        components.host = "capture"
        return components.url ?? URL(fileURLWithPath: "/")
    }()
}

// MARK: - Timeline

struct CaptureEntry: TimelineEntry {
    let date: Date
}

/// One entry, forever: the widget never changes.
struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry {
        CaptureEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        completion(CaptureEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        completion(Timeline(entries: [CaptureEntry(date: .now)], policy: .never))
    }
}

// MARK: - Views

enum CaptureStyle {
    /// RepoMind's accent, the default color of a project.
    static let accent = Color(red: 0.357, green: 0.424, blue: 1.0)

    static var background: some View {
        LinearGradient(
            colors: [Color(red: 0.04, green: 0.04, blue: 0.07), Color(red: 0.11, green: 0.10, blue: 0.24)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct CaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .widgetAccentable()
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("widget_title")
                        .font(.headline)
                    Text("widget_hint_short")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label("widget_title", systemImage: "mic.fill")
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var orb: some View {
        ZStack {
            Circle()
                .fill(CaptureStyle.accent.gradient)
            Image(systemName: "mic.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 52, height: 52)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            orb
            Spacer(minLength: 8)
            Text("widget_title")
                .font(.headline)
                .foregroundStyle(.white)
            Text("widget_hint_short")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            orb
                .scaleEffect(1.25)
                .frame(width: 66, height: 66)
            VStack(alignment: .leading, spacing: 4) {
                Text("widget_title")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("widget_hint_short")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                Text("widget_example")
                    .font(.footnote.italic())
                    .foregroundStyle(CaptureStyle.accent)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }
}
