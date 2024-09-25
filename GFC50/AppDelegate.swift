//
//  AppDelegate.swift
//  GFC50
//
//  Created by Developer on 26/9/2024.
//

import Foundation
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Register a background task to keep the app alive for Bluetooth tasks
        backgroundTask = application.beginBackgroundTask(withName: "BlueToothToMidi") {
            // Cleanup code if background task is about to expire
            application.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        if backgroundTask != .invalid {
            // End the background task when coming back to the foreground
            application.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}
