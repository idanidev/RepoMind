import SwiftData
import SwiftUI

struct TaskCard: View {
    let task: TaskItem

    var body: some View {
        GlassEffectContainer(cornerRadius: 14) {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(task.content))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if task.audioPath != nil {
                    Image(systemName: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(task.content)
        .accessibilityHint(task.audioPath != nil ? "voice_note_content" : "")
    }
}
