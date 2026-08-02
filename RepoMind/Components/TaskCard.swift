import SwiftData
import SwiftUI

struct TaskCard: View {
    let task: TaskItem

    var body: some View {
        GlassEffectContainer(cornerRadius: isMacIdiom ? MacDesign.cardCornerRadius : 14) {
            HStack(spacing: 8) {
                // ✅ FIX: Don't use LocalizedStringKey for user-generated content
                Text(task.content)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if task.audioPath != nil {
                    Image(systemName: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .hoverable(cornerRadius: isMacIdiom ? MacDesign.cardCornerRadius : 14, intensity: 0.04)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var description = task.content
        if task.audioPath != nil {
            description += ", " + String(localized: "voice_note_content")
        }
        return description
    }
}
