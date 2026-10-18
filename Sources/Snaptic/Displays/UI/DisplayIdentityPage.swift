import SwiftUI
import SnapticKit

/// The 0.2 Display Names page id ("displays.identity"), kept until the step-3 exit removes `settingsPages()`. Names,
/// icons, EDID copies and Copy Settings From live in Display Details; the remembered displays, Forget All and EDID
/// export on Display Information, which this shows (PLAN 0.3 §4.3, §4.8, §6.2 ✗).
struct DisplayIdentityPage: View {
    let env: DisplaysPageEnvironment

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        DisplayInformationPage(env: env)
    }
}
