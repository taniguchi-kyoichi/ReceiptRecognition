import Foundation
import LLMStructuredOutputs

@Structured("レシートから抽出した構造化データ")
struct ReceiptData {
    @StructuredField("店舗名") var storeName: String
    @StructuredField("購入日 (YYYY-MM-DD)", .format(.date)) var date: String?
    @StructuredField("購入時刻 (HH:MM)") var time: String?
    @StructuredField("合計金額（税込、整数）", .minimum(0)) var totalAmount: Int?
    @StructuredField("消費税額（整数）", .minimum(0)) var taxAmount: Int?
    @StructuredField("通貨コード", .enum(["JPY", "USD", "EUR"])) var currency: String
    @StructuredField("支払方法") var paymentMethod: String?
    @StructuredField("購入品目リスト") var items: [ReceiptItem]
}

@Structured("レシートの品目")
struct ReceiptItem {
    @StructuredField("品名") var name: String
    @StructuredField("単価（整数）", .minimum(0)) var unitPrice: Int?
    @StructuredField("数量", .minimum(1)) var quantity: Int
    @StructuredField("小計（整数）", .minimum(0)) var subtotal: Int?
}

// MARK: - YAML Serialization

extension ReceiptData {
    func toYAML() -> String {
        var lines: [String] = []

        lines.append("store_name: \(yamlEscape(storeName))")

        if let date {
            lines.append("date: \"\(date)\"")
        }
        if let time {
            lines.append("time: \"\(time)\"")
        }
        if let totalAmount {
            lines.append("total_amount: \(totalAmount)")
        }
        if let taxAmount {
            lines.append("tax_amount: \(taxAmount)")
        }

        lines.append("currency: \(currency)")

        if let paymentMethod {
            lines.append("payment_method: \(yamlEscape(paymentMethod))")
        }

        if !items.isEmpty {
            lines.append("items:")
            for item in items {
                lines.append("  - name: \(yamlEscape(item.name))")
                if let unitPrice = item.unitPrice {
                    lines.append("    unit_price: \(unitPrice)")
                }
                lines.append("    quantity: \(item.quantity)")
                if let subtotal = item.subtotal {
                    lines.append("    subtotal: \(subtotal)")
                }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func yamlEscape(_ value: String) -> String {
        let needsQuoting = value.contains(":") || value.contains("#")
            || value.contains("\"") || value.contains("'")
            || value.hasPrefix(" ") || value.hasSuffix(" ")
            || value.isEmpty
        if needsQuoting {
            let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    // MARK: - YAML Parsing

    static func fromYAML(_ yaml: String) -> ReceiptData? {
        let lines = yaml.components(separatedBy: "\n")
        var topLevel: [String: String] = [:]
        var items: [ReceiptItem] = []
        var inItems = false
        var currentItem: [String: String] = [:]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("- ") {
                // New item entry
                if !currentItem.isEmpty {
                    items.append(parseItem(currentItem))
                    currentItem = [:]
                }
                inItems = true
                let content = String(trimmed.dropFirst(2))
                if let (key, value) = parseKeyValue(content) {
                    currentItem[key] = value
                }
            } else if inItems && !trimmed.contains("items:") {
                if let (key, value) = parseKeyValue(trimmed) {
                    currentItem[key] = value
                }
            } else {
                if let (key, value) = parseKeyValue(trimmed) {
                    if key == "items" { inItems = true; continue }
                    inItems = false
                    topLevel[key] = value
                }
            }
        }
        if !currentItem.isEmpty {
            items.append(parseItem(currentItem))
        }

        guard let storeName = topLevel["store_name"], !storeName.isEmpty else { return nil }

        return ReceiptData(
            storeName: storeName,
            date: topLevel["date"],
            time: topLevel["time"],
            totalAmount: topLevel["total_amount"].flatMap { Int($0) },
            taxAmount: topLevel["tax_amount"].flatMap { Int($0) },
            currency: topLevel["currency"] ?? "JPY",
            paymentMethod: topLevel["payment_method"],
            items: items
        )
    }

    private static func parseKeyValue(_ str: String) -> (String, String)? {
        guard let colonRange = str.range(of: ":") else { return nil }
        let key = str[str.startIndex..<colonRange.lowerBound].trimmingCharacters(in: .whitespaces)
        var value = str[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
        // Strip surrounding quotes
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return (key, value)
    }

    private static func parseItem(_ dict: [String: String]) -> ReceiptItem {
        ReceiptItem(
            name: dict["name"] ?? "",
            unitPrice: dict["unit_price"].flatMap { Int($0) },
            quantity: dict["quantity"].flatMap { Int($0) } ?? 1,
            subtotal: dict["subtotal"].flatMap { Int($0) }
        )
    }
}
