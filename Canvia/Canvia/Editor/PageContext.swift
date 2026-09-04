// Which page a view is drawing, for the things a page needs to know about
// itself: its number, and how many there are.

import SwiftUI

struct PageNumberKey: EnvironmentKey {
    static let defaultValue: (number: Int, count: Int)? = nil
}

extension EnvironmentValues {
    var pageNumber: (number: Int, count: Int)? {
        get { self[PageNumberKey.self] }
        set { self[PageNumberKey.self] = newValue }
    }
}
