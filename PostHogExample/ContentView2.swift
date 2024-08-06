import SwiftUI

struct ContentView2: View {
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoggedIn: Bool = false

    var body: some View {
        NavigationView {
            if isLoggedIn {
                WelcomeView(isLoggedIn: $isLoggedIn)
            } else {
                VStack {
//                    TextField("Email", text: $email)
//                        .padding()
//                        .keyboardType(.emailAddress)
//                        .accessibilityLabel("ph-no-capture")
//                        .autocapitalization(.none)
//                        .border(Color.gray)

//                    SecureField("Password", text: $password)
//                        .padding()
//                        .border(Color.gray)
                    Text("Welcome!")
                        .font(.largeTitle)
                        //                .accessibilityIdentifier("ph-no-capture")
                        .padding()

//                    Button(action: {
//                        // Simple login logic
                    ////                        if !email.isEmpty && !password.isEmpty {
                    ////                            isLoggedIn = true
                    ////                        }
//                        isLoggedIn = true
//                    }) {
//                        Text("Login")
//                            .frame(maxWidth: .infinity)
//                            .padding()
//                            .background(Color.blue)
//                            .foregroundColor(.white)
//                            .cornerRadius(10)
//                    }
//                    .padding(.top, 20)
                }
                .padding()
                .navigationTitle("Login")
            }
        }
    }
}

struct WelcomeView: View {
    @Binding var isLoggedIn: Bool

    var body: some View {
        VStack {
            Text("Welcome!")
                .font(.largeTitle)
//                .accessibilityIdentifier("ph-no-capture")
                .padding()

//            Button(action: {
//                isLoggedIn = false
//            }) {
//                Text("Logout")
//                    .frame(maxWidth: .infinity)
//                    .padding()
//                    .background(Color.red)
//                    .foregroundColor(.white)
//                    .cornerRadius(10)
//            }
//            .padding(.top, 20)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
