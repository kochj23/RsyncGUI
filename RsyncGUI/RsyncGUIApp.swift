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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(jobManager)
                .frame(minWidth: 1000, minHeight: 700)
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
