import SwiftUI

struct RepoMindCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("new_task_command") {
                NotificationCenter.default.post(name: .newTaskShortcut, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Button("sync_repos_command") {
                NotificationCenter.default.post(name: .syncReposShortcut, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button("toggle_view_command") {
                NotificationCenter.default.post(name: .toggleViewShortcut, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("toggle_sidebar") {
                NotificationCenter.default.post(name: .toggleSidebarShortcut, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }

        CommandGroup(replacing: .appSettings) {
            Button("settings_command") {
                NotificationCenter.default.post(name: .openSettingsShortcut, object: nil)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}

extension Notification.Name {
    static let newTaskShortcut = Notification.Name("newTaskShortcut")
    static let syncReposShortcut = Notification.Name("syncReposShortcut")
    static let toggleViewShortcut = Notification.Name("toggleViewShortcut")
    static let openSettingsShortcut = Notification.Name("openSettingsShortcut")
    static let toggleSidebarShortcut = Notification.Name("toggleSidebarShortcut")
}
