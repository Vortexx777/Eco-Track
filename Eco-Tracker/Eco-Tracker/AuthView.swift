import SwiftUI

struct AuthView: View {
    @StateObject private var vm = AuthViewModel()
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Вход")
                .font(.largeTitle)
                .bold()
            
            VStack(spacing: 12) {
                TextField("Логин", text: $vm.login)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)
                
                SecureField("Пароль", text: $vm.password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            
            Button("Войти") {
                vm.signIn()
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.login.isEmpty || vm.password.isEmpty)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(Color.clear)
        .multilineTextAlignment(.center)
    }
}

struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView()
    }
}
