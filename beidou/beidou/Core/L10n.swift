//
//  L10n.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//

import Foundation

enum L10n {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }

    static var appName: String {
        t("app.name")
    }

    static var legalResourceSuffix: String {
        Locale.current.languageCode == "zh" ? "" : "_en"
    }

    static func legalResourceName(_ baseName: String) -> String {
        baseName + legalResourceSuffix
    }
}
