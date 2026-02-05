//
//  RsyncGUIApp.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import SwiftUI
import WidgetKit

@main
struct RsyncGUIApp: App {
    @StateObject private var jobManager = JobManager.shared
    @StateObject private var menuBarManager = MenuBarManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(jobManager)
                .frame(minWidth: 1000, minHeight: 700)
                .task {
                    // Setup menu bar after view appears
                    menuBarManager.setup(jobManager: jobManager)

                    // Sync data to widget on app launch
                    WidgetDataSyncService.shared.syncAllJobData()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // Sync data to widget when app quits
                    WidgetDataSyncService.shared.syncAllJobData()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Sync Job") {
                    jobManager.createNewJob()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
