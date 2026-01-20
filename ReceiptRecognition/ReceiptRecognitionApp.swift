//
//  ReceiptRecognitionApp.swift
//  ReceiptRecognition
//
//  Created by 谷口恭一 on 2026/01/20.
//

import SwiftUI
import DesignSystem

@main
struct ReceiptRecognitionApp: App {
    @State private var themeProvider = ThemeProvider()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .theme(themeProvider)
        }
    }
}
