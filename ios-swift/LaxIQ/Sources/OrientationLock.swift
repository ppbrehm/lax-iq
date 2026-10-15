import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    // Every screen rotates freely with the device except the Game Hub field
    // view and the live Stat Input flow, which lock to landscape while on
    // screen. This overrides whatever rotation lock the device is otherwise set to.
    static let defaultOrientationLock: UIInterfaceOrientationMask = .all
    static var orientationLock: UIInterfaceOrientationMask = defaultOrientationLock

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

private func requestOrientationUpdate(_ mask: UIInterfaceOrientationMask, preferred: UIInterfaceOrientation) {
    AppDelegate.orientationLock = mask

    guard let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
    else { return }

    windowScene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()

    if #available(iOS 16.0, *) {
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }

    // Older, widely-used fallback that reliably forces the rotation even when
    // requestGeometryUpdate is slow to take effect.
    UIDevice.current.setValue(preferred.rawValue, forKey: "orientation")
    UIViewController.attemptRotationToDeviceOrientation()
}

// Counts how many landscape-locked screens are currently on screen. Needed because
// pushing a new screen in a NavigationStack fires the PREVIOUS screen's onDisappear
// almost immediately (even though it's still underneath in the stack) — without this
// count, navigating between two landscape screens (e.g. Game Hub -> Stat Input) would
// have the outgoing screen's onDisappear reset things back to portrait right after the
// incoming screen asked for landscape.
private var landscapeLockCount = 0

private struct LandscapeLock: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                landscapeLockCount += 1
                requestOrientationUpdate(.landscape, preferred: .landscapeRight)
            }
            .onDisappear {
                landscapeLockCount = max(0, landscapeLockCount - 1)
                if landscapeLockCount == 0 {
                    requestOrientationUpdate(AppDelegate.defaultOrientationLock, preferred: .portrait)
                }
            }
    }
}

extension View {
    func lockLandscape() -> some View { modifier(LandscapeLock()) }

    @ViewBuilder
    func lockLandscape(if condition: Bool) -> some View {
        if condition {
            lockLandscape()
        } else {
            self
        }
    }
}
