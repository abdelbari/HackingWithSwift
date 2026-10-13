// A second screen — HDMI or USB-C, or AirPlay — for the room to see the
// slides on while the phone shows the presenter's console.
//
// iOS hands a screen plugged in or AirPlayed to the app as a scene of its
// own, in the role for an external display that takes no touches
// (windowExternalDisplayNonInteractive). The app already runs on scenes —
// the app delegate hands each one its delegate, for the quick actions — so
// the screen is taken that way rather than by watching UIScreen, whose
// connect and disconnect notifications iOS 16 left for scenes: the scene
// connecting is the screen arriving, and its disconnecting the screen
// going. Canvia-Info.plist names the configuration; the app delegate gives
// it this file's scene delegate either way.
//
// The window there shows the talk's slides only, drawn from the same
// PresentSession as the phone — never the notes, the clock or the
// controls. With no talk on it is hidden, so the screen shows the phone as
// it did before.

import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class ExternalDisplay {
    static let shared = ExternalDisplay()

    /// The scene configuration's name in Canvia-Info.plist.
    static let configurationName = "External Display"

    /// The window on the screen attached; nil with none.
    private(set) var window: UIWindow?

    /// The talk on, which the screen shows; nil between talks.
    var session: PresentSession? {
        didSet { window?.isHidden = session == nil }
    }

    /// Whether a screen is attached, so Present shows the console.
    var attached: Bool { window != nil }

    /// A screen arrived: its window, showing the talk when there is one.
    func attach(_ window: UIWindow) {
        window.isHidden = session == nil
        self.window = window
    }

    /// The screen went: the phone presents again, on the same page.
    func detach(_ window: UIWindow) {
        guard window === self.window else { return }
        window.isHidden = true
        self.window = nil
    }
}

/// The scene a screen comes as: one window, the slides in it.
@MainActor
final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = UIHostingController(rootView: ExternalSlidesView())
        self.window = window
        ExternalDisplay.shared.attach(window)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if let window { ExternalDisplay.shared.detach(window) }
        window = nil
    }
}

/// What the room sees: the talk's page full screen on black, as the phone
/// shows it without a second screen — the same renderer, transitions,
/// exits and clips — and the pointer. Never the notes.
struct ExternalSlidesView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let session = ExternalDisplay.shared.session {
                    PresentStage(session: session, size: geo.size)
                }
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
    }
}
