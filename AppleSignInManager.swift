import Foundation
import AuthenticationServices
import FirebaseAuth
import CryptoKit

class AppleSignInManager: NSObject, ObservableObject {
    @Published var isSigningIn = false
    @Published var errorMessage: String?
    
    private var currentNonce: String?
    private var completionHandler: ((Result<AppleSignInResult, Error>) -> Void)?
    
    func signInWithApple(completion: @escaping (Result<AppleSignInResult, Error>) -> Void) {
        isSigningIn = true
        errorMessage = nil
        self.completionHandler = completion
        
        let nonce = randomNonceString()
        currentNonce = nonce
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: Array<Character> =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            return String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    private func encodeForFirebase(_ string: String) -> String {
        return string
            .replacingOccurrences(of: ".", with: "_DOT_")
            .replacingOccurrences(of: "#", with: "_HASH_")
            .replacingOccurrences(of: "$", with: "_DOLLAR_")
            .replacingOccurrences(of: "[", with: "_LBRACKET_")
            .replacingOccurrences(of: "]", with: "_RBRACKET_")
    }
}

extension AppleSignInManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let nonce = currentNonce else {
                let error = NSError(domain: "AppleSignIn", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid state: A login callback was received, but no login request was sent."])
                DispatchQueue.main.async {
                    self.isSigningIn = false
                    self.completionHandler?(.failure(error))
                }
                return
            }
            
            guard let appleIDToken = appleIDCredential.identityToken else {
                let error = NSError(domain: "AppleSignIn", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch identity token"])
                DispatchQueue.main.async {
                    self.isSigningIn = false
                    self.completionHandler?(.failure(error))
                }
                return
            }
            
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                let error = NSError(domain: "AppleSignIn", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to serialize token string from data"])
                DispatchQueue.main.async {
                    self.isSigningIn = false
                    self.completionHandler?(.failure(error))
                }
                return
            }
            
            // Create Firebase credential
            let credential = OAuthProvider.credential(withProviderID: "apple.com",
                                                      idToken: idTokenString,
                                                      rawNonce: nonce)
            
            // Sign in to Firebase
            Auth.auth().signIn(with: credential) { [weak self] (authResult, error) in
                DispatchQueue.main.async {
                    self?.isSigningIn = false
                    
                    if let error = error {
                        print("Firebase sign in error: \(error.localizedDescription)")
                        self?.completionHandler?(.failure(error))
                        return
                    }
                    
                    guard let user = authResult?.user else {
                        let error = NSError(domain: "AppleSignIn", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to get user information"])
                        self?.completionHandler?(.failure(error))
                        return
                    }
                    
                    print("Firebase sign in successful for user: \(user.uid)")
                    
                    // Extract name from Apple credential
                    let fullName = appleIDCredential.fullName
                    let displayName = [fullName?.givenName, fullName?.familyName]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    
                    // Encode the Apple User ID for Firebase safety
                    let encodedAppleUserID = self?.encodeForFirebase(appleIDCredential.user) ?? appleIDCredential.user
                    
                    print("Apple User ID: \(appleIDCredential.user)")
                    print("Encoded Apple User ID: \(encodedAppleUserID)")
                    print("Display Name from Apple: \(displayName)")
                    
                    let result = AppleSignInResult(
                        appleUserID: appleIDCredential.user,
                        encodedAppleUserID: encodedAppleUserID,
                        firebaseUID: user.uid,
                        email: appleIDCredential.email,
                        displayName: displayName.isEmpty ? nil : displayName
                    )
                    
                    print("Calling completion handler with result")
                    self?.completionHandler?(.success(result))
                }
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        DispatchQueue.main.async {
            self.isSigningIn = false
            print("Apple Sign In error: \(error.localizedDescription)")
            self.completionHandler?(.failure(error))
        }
    }
}

extension AppleSignInManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

struct AppleSignInResult {
    let appleUserID: String
    let encodedAppleUserID: String
    let firebaseUID: String
    let email: String?
    let displayName: String?
}
