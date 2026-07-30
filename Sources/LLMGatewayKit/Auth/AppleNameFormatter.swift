import Foundation

/// 把 Apple 登录返回的 `PersonNameComponents`（仅首次授权才有）格式化成可作昵称的字符串。
/// 用系统 `PersonNameComponentsFormatter` 按当前 locale 排序：日文 →「田中太郎」家姓在前；
/// 西文 →「Taro Tanaka」。空组件或仅空白返回 nil（调用方据此决定不上报 displayName）。
enum AppleNameFormatter {
    /// 与网关 `sanitizeDisplayName` 保持一致：昵称最多 24 个扩展字素。
    /// Apple 的姓名页允许用户在授权时临时修改内容；无效输入只应降级为「不带初始昵称」登录，
    /// 不能让一次性的 Apple 授权结果阻断账号创建。
    static let maxGraphemes = 24

    static func string(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatted = PersonNameComponentsFormatter().string(from: components)
        return sanitize(formatted)
    }

    static func sanitize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let withoutControls = String(raw.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        })
        let trimmed = withoutControls.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxGraphemes else { return nil }
        return trimmed
    }
}
