import Foundation

private final class BundleToken {}

extension Bundle {
    /// The bundle that holds `Localizable.xcstrings` for the code running here.
    /// `Shared` is a source of every target, so the catalog is compiled into the
    /// app, the Watch app, both widget extensions and the unit-test bundle. The
    /// logic tests are not hosted by the app, so `Bundle.main` there is the test
    /// runner; resolving through a class in this file finds the right bundle in
    /// all of them.
    static let recharge = Bundle(for: BundleToken.self)
}
