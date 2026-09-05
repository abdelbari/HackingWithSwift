// The design being edited, as a user activity: Siri suggests it back,
// Spotlight's "recent" knows it, and Handoff can continue it on another
// device that has the same design.

import Foundation

enum DesignActivity {
    static let type = "com.canvia.design"

    static func configure(_ activity: NSUserActivity, design: Design) {
        activity.title = design.title
        activity.userInfo = ["id": design.id]
        activity.requiredUserInfoKeys = ["id"]
        activity.persistentIdentifier = design.id
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.isEligibleForHandoff = true
    }

    static func designID(from activity: NSUserActivity) -> String? {
        guard activity.activityType == type else { return nil }
        return activity.userInfo?["id"] as? String
    }
}
