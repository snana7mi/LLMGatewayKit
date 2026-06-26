import Foundation

/// 把 Apple 登录返回的 `PersonNameComponents`（仅首次授权才有）格式化成可作昵称的字符串。
/// 用系统 `PersonNameComponentsFormatter` 按当前 locale 排序：日文 →「田中太郎」家姓在前；
/// 西文 →「Taro Tanaka」。空组件或仅空白返回 nil（调用方据此决定不上报 displayName）。
enum AppleNameFormatter {
    static func string(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatted = PersonNameComponentsFormatter().string(from: components)
        let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
