//
//  RsyncGUIApp.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import SwiftUI

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
