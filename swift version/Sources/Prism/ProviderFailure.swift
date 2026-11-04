import Foundation

/// Apply the same header rules to discovery, chat, summaries, search and balance.
enum APICredentials {
    static func normalized(_ input: String) throws -> String {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DeepSeekError.missingAPIKey }
        guard !key.lowercased().hasPrefix("bearer"), key.unicodeScalars.allSatisfy({
            (33...126).contains($0.value) && $0 != "\"" && $0 != "'"
        }) else { throw DeepSeekError.malformedAPIKey }
        return key
    }
}

/// Provider bodies can echo credentials; never display or log their raw text.
enum ProviderFailure {
    static func localized(_ simplified: String, _ traditional: String, _ english: String, language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: simplified
        case .traditionalChinese: traditional
        case .english: english
        }
    }

    static func httpMessage(_ status: Int, language: AppLanguage) -> String {
        let text: String
        switch status {
        case 401:
            text = localized("密钥验证失败：当前 API Key 无效或已被撤销。请到设置中重新粘贴并验证，也请确认服务地址与密钥所属平台一致。", "密鑰驗證失敗：目前的 API Key 無效或已被撤銷。請到設定中重新貼上並驗證，並確認服務地址與密鑰所屬平台一致。", "The API key was rejected. Re-enter and verify it in Settings, and check that the service URL matches the key's provider.", language: language)
        case 402:
            text = localized("账户余额不足，请到服务平台检查余额并充值后重试。", "帳戶餘額不足，請到服務平台檢查餘額並儲值後重試。", "Your account has insufficient credit. Check your provider balance and top up before retrying.", language: language)
        case 403:
            text = localized("服务拒绝访问，请确认账户、密钥或所选模型的使用权限。", "服務拒絕存取，請確認帳戶、密鑰或所選模型的使用權限。", "Access was denied. Check your account, API key and model permissions.", language: language)
        case 404:
            text = localized("找不到接口或模型，请检查服务地址和模型名称，或重新获取模型列表。", "找不到介面或模型，請檢查服務地址和模型名稱，或重新取得模型清單。", "The endpoint or model was not found. Check the service URL and refresh the model list.", language: language)
        case 400, 422:
            text = localized("服务无法接受本次请求，请检查模型和推理参数；若持续出现，请更新 Prism 或更换模型后重试。", "服務無法接受本次請求，請檢查模型和推理參數；若持續出現，請更新 Prism 或更換模型後重試。", "The service rejected the request format or parameters. Check the model and reasoning settings; update Prism if it persists.", language: language)
        case 429:
            text = localized("请求过于频繁或已达到服务限额，请稍等片刻再试。", "請求過於頻繁或已達到服務限額，請稍候再試。", "The request rate or service quota was exceeded. Wait a moment and retry.", language: language)
        case 500...599:
            text = localized("服务暂时繁忙或发生故障，请稍后重试。", "服務暫時繁忙或發生故障，請稍後重試。", "The service is busy or temporarily unavailable. Please retry shortly.", language: language)
        default:
            text = localized("服务未能完成请求，请检查设置或稍后重试。", "服務未能完成請求，請檢查設定或稍後重試。", "The service could not complete the request. Check Settings or retry later.", language: language)
        }
        return text + " (HTTP \(status))"
    }

    static func message(_ error: any Error, language: AppLanguage) -> String {
        if let error = error as? DeepSeekError {
            switch error {
            case .http(let status): return httpMessage(status, language: language)
            case .missingAPIKey: return localized("请先在设置中填写 API Key。", "請先在設定中填寫 API Key。", "Enter your API key in Settings first.", language: language)
            case .malformedAPIKey: return localized("密钥格式不正确，请只粘贴 Key 本身，不要包含空格、引号或 Bearer 前缀。", "密鑰格式不正確，請只貼上 Key 本身，不要包含空格、引號或 Bearer 前綴。", "Paste only the API key, without spaces, quotes or a Bearer prefix.", language: language)
            case .invalidBaseURL: return localized("服务地址无效，请填写完整的 http 或 https 地址。", "服務地址無效，請填寫完整的 http 或 https 地址。", "Enter a valid http or https service URL.", language: language)
            case .invalidModel: return localized("尚未选择模型，请获取模型列表后选择。", "尚未選擇模型，請取得模型清單後選擇。", "Select a model after refreshing the model list.", language: language)
            case .emptyResponse: return localized("服务没有返回有效内容，请重试。", "服務沒有返回有效內容，請重試。", "The service returned no usable content. Please retry.", language: language)
            case .invalidResponse: break
            case .api(let detail):
                // This case is used only for client-authored messages.
                return detail
            }
        }
        if let url = error as? URLError {
            if url.code == .timedOut {
                return localized("连接超时，请检查网络或服务地址后重试。", "連線逾時，請檢查網路或服務地址後重試。", "The connection timed out. Check your network and service URL.", language: language)
            }
            return localized("无法连接到服务，请检查网络、代理和服务地址。", "無法連線到服務，請檢查網路、代理和服務地址。", "Unable to connect. Check your network, proxy and service URL.", language: language)
        }
        return localized("无法读取服务返回的内容，请检查服务地址和接口兼容性后重试。", "無法讀取服務傳回的內容，請檢查服務地址和介面相容性後重試。", "The response could not be read. Check the service URL and API compatibility.", language: language)
    }
}
