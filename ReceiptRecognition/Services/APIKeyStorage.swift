//
//  APIKeyStorage.swift
//  ReceiptRecognition
//
//  Created by Claude on 2026/01/20.
//

import Foundation

/// APIキーの永続化管理
enum APIKeyStorage {
    private static let geminiAPIKeyKey = "GEMINI_API_KEY"

    /// Gemini APIキーを取得（UserDefaults優先、なければ環境変数から取得して保存）
    static var geminiAPIKey: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: geminiAPIKeyKey), !saved.isEmpty {
                return saved
            }
            // 環境変数から取得して保存
            if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.isEmpty {
                UserDefaults.standard.set(envKey, forKey: geminiAPIKeyKey)
                return envKey
            }
            return ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: geminiAPIKeyKey)
        }
    }

    /// APIキーが設定されているか
    static var hasAPIKey: Bool {
        !geminiAPIKey.isEmpty
    }
}
