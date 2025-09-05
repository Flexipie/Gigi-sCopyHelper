//
//  GigiCopyHelperApp.swift
//  GigiCopyHelper
//
//  Created by Felix Westin on 2025-09-04.
//

import SwiftUI

@main
struct GigiCopyHelperApp: App {
    // Use AppDelegate to create the status bar item and hotkey.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window for a menubar app. Provide a minimal Settings scene for completeness.
        Settings {
            ContentView()
        }
    }
}
