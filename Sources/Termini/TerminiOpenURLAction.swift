import Foundation
import GhosttyKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum TerminiOpenURLAction {
    @MainActor
    static func handle(_ action: ghostty_action_open_url_s) -> Bool {
        #if canImport(AppKit)
        handle(action, using: { NSWorkspace.shared.open($0) })
        #elseif canImport(UIKit)
        handle(action, using: { url in
            UIApplication.shared.open(url)
            return true
        })
        #else
        false
        #endif
    }

    static func handle(
        _ action: ghostty_action_open_url_s,
        using opener: (URL) -> Bool
    ) -> Bool {
        guard let url = url(from: action) else { return false }
        return opener(url)
    }

    static func url(from action: ghostty_action_open_url_s) -> URL? {
        guard let bytes = action.url,
              action.len > 0,
              action.len <= UInt(Int.max) else {
            return nil
        }

        let data = Data(bytes: bytes, count: Int(action.len))
        guard let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            return nil
        }

        if let url = URL(string: value), url.scheme != nil {
            return url
        }

        return URL(fileURLWithPath: NSString(string: value).standardizingPath)
    }
}
