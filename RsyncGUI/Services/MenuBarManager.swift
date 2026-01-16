//
//  MenuBarManager.swift
//  RsyncGUI
//
//  Menu bar integration for quick access to sync jobs
//
//  Created by Jordan Koch on 1/15/2026.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import AppKit
import SwiftUI
import Foundation
import Combine

@MainActor
class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var jobManager: JobManager?

    @Published var isMenuBarVisible = true

    func setup(jobManager: JobManager) {
        self.jobManager = jobManager

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateIcon()
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }

        updateMenu()
    }

    func updateIcon() {
        guard let button = statusItem?.button else { return }

        // Always show sync icon (we don't track running state easily)
        button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.circle", accessibilityDescription: "RsyncGUI")
        button.image?.isTemplate = true
    }

    func updateMenu() {
        let menu = NSMenu()

        // Header
        let headerItem = NSMenuItem(title: "RsyncGUI", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // Quick actions
        let newJobItem = NSMenuItem(title: "New Sync Job...", action: #selector(createNewJob), keyEquivalent: "n")
        newJobItem.target = self
        menu.addItem(newJobItem)

        // Recent jobs
        if let recentJobs = jobManager?.jobs.prefix(5), !recentJobs.isEmpty {
            let recentMenu = NSMenu()
            for job in recentJobs {
                let jobItem = NSMenuItem(title: job.name, action: #selector(startRecentJob(_:)), keyEquivalent: "")
                jobItem.target = self
                jobItem.representedObject = job
                recentMenu.addItem(jobItem)
            }

            let recentItem = NSMenuItem(title: "Recent Jobs", action: nil, keyEquivalent: "")
            recentItem.submenu = recentMenu
            menu.addItem(recentItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Show/Hide Window
        let showItem = NSMenuItem(title: "Show RsyncGUI", action: #selector(showMainWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit RsyncGUI", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func statusBarButtonClicked() {
        updateMenu()
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func createNewJob() {
        showMainWindow()
        Task { @MainActor in
            jobManager?.createNewJob()
        }
    }

    @objc private func startRecentJob(_ sender: NSMenuItem) {
        // Job ID passed as represented object
        showMainWindow()
        // User will see the job selected in UI
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
