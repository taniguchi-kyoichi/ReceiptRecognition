//
//  ReceiptAnalysis.swift
//  ReceiptRecognition
//
//  Created by Claude on 2026/01/20.
//

import Foundation
import LLMStructuredOutputs

// MARK: - Receipt Analysis Result

/// レシート解析結果（画像入力用）
@Structured("レシート解析結果")
struct ReceiptAnalysis {
    /// レシートかどうか
    @StructuredField("レシートかどうか。ボケ・ブレ・不鮮明ならfalse")
    var isReceipt: Bool

    /// 日付（レシートの場合）
    @StructuredField("日付（YYYY-MM-DD形式）")
    var date: String?
}

// MARK: - Receipt Analysis from OCR Text

/// レシート解析結果（OCRテキスト用）
@Structured("レシート解析結果")
struct ReceiptAnalysisFromText {
    /// レシートかどうか
    @StructuredField("レシートかどうか")
    var isReceipt: Bool

    /// 日付（レシートの場合）
    @StructuredField("日付（YYYY-MM-DD形式）")
    var date: String?
}

// MARK: - Analysis Method

/// 解析方法
enum AnalysisMethod: String {
    /// 画像を直接送信（マルチモーダル）
    case imageInput = "画像入力"

    /// OCR → テキスト送信
    case ocrText = "OCR + テキスト"
}

// MARK: - Analysis Result

/// 解析結果（コスト情報付き）
struct AnalysisResult {
    /// 解析方法
    let method: AnalysisMethod

    /// レシートかどうか
    let isReceipt: Bool

    /// 日付
    let date: String?

    /// 入力トークン数
    let inputTokens: Int

    /// 出力トークン数
    let outputTokens: Int

    /// 処理時間（秒）
    let processingTime: TimeInterval

    /// OCR処理時間（OCR方式の場合のみ）
    let ocrTime: TimeInterval?

    /// OCRテキスト（OCR方式の場合のみ）
    let ocrText: String?

    /// 矩形が検出されたか（OCR方式の場合のみ）
    let rectangleDetected: Bool?

    /// 合計トークン数
    var totalTokens: Int {
        inputTokens + outputTokens
    }
}
