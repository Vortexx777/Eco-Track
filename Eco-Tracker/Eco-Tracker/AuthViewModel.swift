import SwiftUI
import Combine

final class AuthViewModel: ObservableObject {
    @AppStorage("isAuthenticated") var isAuthenticated: Bool = false
    @AppStorage("userName") var userName: String = ""

    @Published var login: String = ""
    @Published var password: String = ""

    func signIn() {
        guard !login.isEmpty, !password.isEmpty else { return }
        userName = login
        isAuthenticated = true
    }

    func signOut() {
        isAuthenticated = false
        userName = ""
        login = ""
        password = ""
    }
}
