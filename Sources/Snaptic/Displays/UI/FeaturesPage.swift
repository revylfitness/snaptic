import SwiftUI
import SnapticKit

/// The 0.2 Display Features page id ("displays.features"), kept until the step-3 exit removes `settingsPages()`: it
/// shows the feature switches of Displays › Advanced (PLAN 0.3 §4.3, §6.2 ✗).
struct FeaturesPage: View {
    let env: DisplaysPageEnvironment

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        DisplaysFeaturesPage(env: env)
    }
}
