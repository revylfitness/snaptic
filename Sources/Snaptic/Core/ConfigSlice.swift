import Combine
import Foundation
import SnapticKit

/// Publishes only when `store.value[keyPath:]` changes (lead; PLAN 0.3 §4.5): a 15 Hz slider commit re-renders the
/// one section reading that slice, not the whole page. A view owns it as `@StateObject` (or reads one cached in the
/// environment), never creates it in `body`.
@MainActor final class ConfigSlice<T: ConfigModel, V: Equatable>: ObservableObject {
    @Published private(set) var value: V
    private var sink: AnyCancellable?

    init(_ store: ConfigStore<T>, _ keyPath: KeyPath<T, V>) {
        value = store.value[keyPath: keyPath]
        sink = store.$value
            .map { $0[keyPath: keyPath] }
            .removeDuplicates()
            .sink { [weak self] new in
                MainActor.assumeIsolated {
                    guard let self, self.value != new else { return }
                    self.value = new
                }
            }
    }
}
