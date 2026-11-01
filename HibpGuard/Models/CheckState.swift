import Foundation

enum CheckState<Value> {
    case idle
    case loading
    case success(Value)
    case failure(AppError)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
