# ReceiptRecognition

レシート認識iOSアプリ。Gemini APIを使用して、2つの方式でレシート判定を比較します。

## 方式比較

| 方式 | 説明 |
|------|------|
| 画像入力 | 画像を直接Geminiに送信（マルチモーダル） |
| OCR+テキスト | iOS標準OCRでテキスト抽出後、Geminiに送信 |

## セットアップ

### 1. Gemini API Keyの取得

[Google AI Studio](https://aistudio.google.com/apikey) でAPIキーを取得

### 2. 環境変数の設定

Xcodeで `Product` → `Scheme` → `Edit Scheme` → `Run` → `Arguments` → `Environment Variables` に追加:

```
GEMINI_API_KEY = your_api_key_here
```

または、アプリ内の設定画面から直接APIキーを入力することも可能です。

## 使用技術

- SwiftUI
- Vision Framework (OCR)
- [swift-llm-structured-outputs](https://github.com/no-problem-dev/swift-llm-structured-outputs) (Gemini API)
- Gemini 2.5 Flash-Lite

## 出力

- `isReceipt`: レシートかどうか (Bool)
- `date`: 日付 (YYYY-MM-DD形式)
- トークン使用量・処理時間の比較
