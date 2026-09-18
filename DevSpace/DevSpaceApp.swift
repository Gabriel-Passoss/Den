//
//  DevSpaceApp.swift
//  DevSpace
//
//  Created by Gabriel dos Passos on 16/09/26.
//

import SwiftUI

@main
struct DevSpaceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
    }
}
