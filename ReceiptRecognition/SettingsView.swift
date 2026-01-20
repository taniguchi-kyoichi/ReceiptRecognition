//
//  SettingsView.swift
//  ReceiptRecognition
//
//  Created by Claude on 2026/01/20.
//

import SwiftUI
import DesignSystem

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorPalette) private var colors

    @State private var apiKey: String = APIKeyStorage.geminiAPIKey

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Gemini API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                } header: {
                    Text("API設定")
                } footer: {
                    Text("APIキーを変更した場合、アプリを再起動すると反映されます")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        APIKeyStorage.geminiAPIKey = apiKey
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .theme(ThemeProvider())
}
