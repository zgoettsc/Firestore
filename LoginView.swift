import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 242/255, green: 247/255, blue: 255/255).ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // App Logo and Title
                    VStack(spacing: 20) {
                        Image(systemName: "fork.knife")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.blue)
                        
                        Text("Tolerance Tracker")
                            .font(.largeTitle.bold())
                            .foregroundColor(.blue)
                        
                        Text("Track your daily progress")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Apple Sign In Button
                    VStack(spacing: 20) {
                        if authViewModel.isProcessing {
                            ProgressView("Signing in...")
                                .frame(height: 50)
                        } else {
                            SignInWithAppleButton(
                                onRequest: { request in
                                    // This is handled by our AppleSignInManager
                                },
                                onCompletion: { result in
                                    // This is also handled by our AppleSignInManager
                                }
                            )
                            .frame(height: 50)
                            .cornerRadius(8)
                            .onTapGesture {
                                authViewModel.signInWithApple()
                            }
                        }
                        
                        // Error Message
                        if let errorMessage = authViewModel.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $authViewModel.showingNameInput) {
            if let result = authViewModel.pendingAppleSignInResult {
                NameInputView(
                    isPresented: $authViewModel.showingNameInput,
                    appleSignInResult: result,
                    onNameSubmitted: { name in
                        authViewModel.completeNameInput(name: name)
                    }
                )
            }
        }
        .onChange(of: authViewModel.authState) { _, newState in
            if newState == .signedIn {
                dismiss()
            }
        }
    }
}
