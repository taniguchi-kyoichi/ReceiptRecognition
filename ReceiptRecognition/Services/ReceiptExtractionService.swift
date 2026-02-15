import LLMStructuredOutputs

protocol ReceiptExtractionService: Sendable {
    /// 通常抽出（Flash 3 — 撮影直後の高速処理用）
    func extract(from ocrText: String) async throws -> ReceiptData
    /// 再解析（Pro — 詳細画面からの精度重視処理用）
    func reExtract(from ocrText: String) async throws -> ReceiptData
}

struct GeminiReceiptExtractionService: ReceiptExtractionService {
    private let client: GeminiClient

    init(apiKey: String) {
        self.client = GeminiClient(apiKey: apiKey)
    }

    func extract(from ocrText: String) async throws -> ReceiptData {
        try await client.generate(
            input: LLMInput(stringLiteral: ocrText),
            model: .flash3,
            systemPrompt: Self.systemPrompt,
            temperature: 0.0
        )
    }

    func reExtract(from ocrText: String) async throws -> ReceiptData {
        try await client.generate(
            input: LLMInput(stringLiteral: ocrText),
            model: .pro25,
            systemPrompt: Self.reExtractSystemPrompt,
            temperature: 0.0
        )
    }

    private static let systemPrompt = """
        あなたはレシートOCRテキストから構造化データを抽出する専門家です。

        ## ルール
        - 店舗名はレシート上部に記載されていることが多い
        - 合計金額は「合計」「計」「TOTAL」などのキーワードの横にある数値
        - 日付は「yyyy/MM/dd」「yyyy年MM月dd日」など様々な形式がある → YYYY-MM-DD に変換
        - 時刻は「HH:mm」「HH時mm分」など → HH:MM に変換
        - OCR誤認識を考慮: 「0」と「O」、「1」と「l」、「円」と「回」など
        - 金額にカンマが含まれる場合は除去して整数にする
        - 不明な項目は null にする（推測で埋めない）
        - 通貨は日本のレシートなら JPY、判断できない場合も JPY をデフォルトとする
        - 品目の数量が明示されていない場合は 1 とする
        """

    private static let reExtractSystemPrompt = """
        あなたはレシートOCRテキストから構造化データを抽出する専門家です。
        これは再解析リクエストです。前回の抽出結果が不正確だったため、特に慎重に解析してください。

        ## ルール
        - 店舗名はレシート上部に記載されていることが多い。チェーン店名と支店名を両方含める
        - 合計金額は「合計」「計」「TOTAL」「お買上」などのキーワードの横にある数値
        - 小計・値引き・税がある場合、最終的な支払金額を合計とする
        - 日付は「yyyy/MM/dd」「yyyy年MM月dd日」など様々な形式がある → YYYY-MM-DD に変換
        - 時刻は「HH:mm」「HH時mm分」など → HH:MM に変換
        - OCR誤認識を特に注意深く考慮する:
          - 「0」と「O」、「1」と「l」と「I」、「5」と「S」、「8」と「B」
          - 「円」と「回」と「円」、「点」と「占」
          - 半角・全角の混在
        - 金額にカンマ・スペースが含まれる場合は除去して整数にする
        - 品目名が途中で切れている場合は、前後の文脈から推測してよい
        - 値引き行（マイナス金額）は品目として含め、subtotal を負の値にする
        - 不明な項目は null にする
        - 通貨は日本のレシートなら JPY
        - 品目の数量が明示されていない場合は 1 とする
        - 税率表示（※8%、*10% など）がある場合は無視してよい
        """
}
