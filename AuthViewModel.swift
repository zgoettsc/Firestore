import Foundation
import FirebaseAuth
import Combine
import FirebaseDatabase
import RevenueCat

class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .loading
    @Published var currentUser: AuthUser?
    @Published var errorMessage: String?
    @Published var isProcessing = false
    @Published var showingNameInput = false
    @Published var pendingAppleSignInResult: AppleSignInResult?
    
    private var authStateHandler: AuthStateDidChangeListenerHandle?
    private let appleSignInManager = AppleSignInManager()
    
    init() {
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            
            print("Auth state changed. User: \(user?.uid ?? "nil")")
            
            if let user = user {
                self.currentUser = AuthUser(user: user)
                self.authState = .signedIn
                print("User signed in: \(user.uid)")
            } else {
                self.currentUser = nil
                self.authState = .signedOut
                print("User signed out")
            }
        }
    }
    
    deinit {
        if let authStateHandler = authStateHandler {
            Auth.auth().removeStateDidChangeListener(authStateHandler)
        }
    }
    
    func signInWithApple() {
        print("Starting Apple Sign In")
        isProcessing = true
        errorMessage = nil
        
        appleSignInManager.signInWithApple { [weak self] result in
            DispatchQueue.main.async {
                self?.isProcessing = false
                
                switch result {
                case .success(let appleResult):
                    print("Apple Sign In successful, handling result")
                    self?.handleAppleSignInResult(appleResult)
                case .failure(let error):
                    print("Apple Sign In failed: \(error.localizedDescription)")
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func handleAppleSignInResult(_ result: AppleSignInResult) {
        print("Handling Apple Sign In result for encoded ID: \(result.encodedAppleUserID)")
        
        // Check if this Apple ID already has an account using encoded ID
        checkForExistingAppleAccount(appleUserID: result.encodedAppleUserID) { [weak self] existingUser in
            DispatchQueue.main.async {
                if let existingUser = existingUser {
                    print("Found existing user: \(existingUser.name)")
                    // User already exists, sign them in
                    self?.completeSignIn(existingUser: existingUser, result: result)
                } else {
                    print("No existing user found, creating new account")
                    // New user, check if we have a name
                    if let displayName = result.displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        print("Using name from Apple: \(displayName)")
                        // We have a name from Apple, create account
                        self?.createNewAccount(with: result, name: displayName)
                    } else {
                        print("No name from Apple, showing name input")
                        // No name from Apple, show name input
                        self?.pendingAppleSignInResult = result
                        self?.showingNameInput = true
                    }
                }
            }
        }
    }
    
    func completeNameInput(name: String) {
        guard let result = pendingAppleSignInResult else {
            print("No pending Apple sign in result")
            return
        }
        
        print("Completing name input with name: \(name)")
        showingNameInput = false
        pendingAppleSignInResult = nil
        
        // Add a small delay to ensure UI updates properly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.createNewAccount(with: result, name: name)
        }
    }
    
    private func checkForExistingAppleAccount(appleUserID: String, completion: @escaping (User?) -> Void) {
        let dbRef = Database.database().reference()
        
        print("Checking for existing account with ID: \(appleUserID)")
        
        // Check if Apple ID exists in auth_mapping
        dbRef.child("auth_mapping").child(appleUserID).observeSingleEvent(of: .value) { snapshot in
            print("Auth mapping check result: exists=\(snapshot.exists())")
            
            guard let userIdString = snapshot.value as? String,
                  let userId = UUID(uuidString: userIdString) else {
                print("No existing mapping found")
                completion(nil)
                return
            }
            
            print("Found mapping to user ID: \(userIdString)")
            
            // Get the user data
            dbRef.child("users").child(userIdString).observeSingleEvent(of: .value) { userSnapshot in
                print("User data check result: exists=\(userSnapshot.exists())")
                
                guard let userData = userSnapshot.value as? [String: Any],
                      let user = User(dictionary: userData) else {
                    print("Failed to load user data")
                    completion(nil)
                    return
                }
                
                print("Successfully loaded existing user: \(user.name)")
                completion(user)
            }
        }
    }
    
    private func completeSignIn(existingUser: User, result: AppleSignInResult) {
        print("Completing sign in for existing user: \(existingUser.name)")
        
        // Link RevenueCat to Firebase UID - THIS IS THE KEY ADDITION
        Purchases.shared.logIn(result.firebaseUID) { (customerInfo, created, error) in
            if let error = error {
                print("RevenueCat login error: \(error.localizedDescription)")
            } else {
                print("RevenueCat linked to Firebase UID: \(result.firebaseUID)")
            }
        }
        
        // Post notification immediately with the existing user
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("AuthUserSignedIn"),
                object: nil,
                userInfo: ["authUser": self.currentUser as Any, "appUser": existingUser]
            )
            
            print("Posted AuthUserSignedIn notification for existing user: \(existingUser.name)")
        }
        
        checkAndShowOnboarding()
    }
    
    private func createNewAccount(with result: AppleSignInResult, name: String) {
        print("Creating new account with name: \(name)")
        
        let userId = UUID()
        let userIdString = userId.uuidString
        
        // Link RevenueCat to Firebase UID - THIS IS THE KEY ADDITION
        Purchases.shared.logIn(result.firebaseUID) { (customerInfo, created, error) in
            if let error = error {
                print("RevenueCat login error: \(error.localizedDescription)")
            } else {
                print("RevenueCat linked to Firebase UID: \(result.firebaseUID)")
            }
        }
        
        // Create the app user with Apple ID as the auth identifier
        let newUser = User(
            id: userId,
            name: name,
            isAdmin: true,
            authId: result.appleUserID, // Store original Apple ID
            remindersEnabled: [:],
            reminderTimes: [:],
            treatmentFoodTimerEnabled: true,
            treatmentTimerDuration: 900,
            ownedRooms: nil,
            subscriptionPlan: nil,
            roomLimit: 0
        )
        
        let dbRef = Database.database().reference()
        
        print("Saving auth mapping: \(result.encodedAppleUserID) -> \(userIdString)")
        
        // Save auth mapping: Encoded Apple ID -> App User ID
        dbRef.child("auth_mapping").child(result.encodedAppleUserID).setValue(userIdString) { error, _ in
            if let error = error {
                print("Error creating auth mapping: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to create account: \(error.localizedDescription)"
                }
                return
            }
            
            print("Auth mapping saved successfully")
            
            // Save user data
            dbRef.child("users").child(userIdString).setValue(newUser.toDictionary()) { error, _ in
                if let error = error {
                    print("Error creating user: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to create user data: \(error.localizedDescription)"
                    }
                } else {
                    print("Successfully created user for Apple ID: \(result.appleUserID)")
                    UserDefaults.standard.set(userIdString, forKey: "currentUserId")
                    
                    DispatchQueue.main.async {
                        // Post notification with the new user
                        print("Posting AuthUserSignedIn notification")
                        NotificationCenter.default.post(
                            name: Notification.Name("AuthUserSignedIn"),
                            object: nil,
                            userInfo: ["authUser": self.currentUser as Any, "appUser": newUser]
                        )
                    }
                }
            }
        }
        
        checkAndShowOnboarding()
    }
    
    
    func checkAndShowOnboarding() {
        // Post a delayed notification so it happens after the user is fully set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                NotificationCenter.default.post(
                    name: Notification.Name("ShowOnboardingTutorial"),
                    object: nil
                )
            }
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.authState = .signedOut
            self.currentUser = nil
            self.showingNameInput = false
            self.pendingAppleSignInResult = nil
            self.errorMessage = nil
            print("User signed out successfully")
        } catch {
            self.errorMessage = "Error signing out: \(error.localizedDescription)"
            print("Sign out error: \(error.localizedDescription)")
        }
    }
    
    func deleteAccount(completion: @escaping (Bool, String?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false, "No user is signed in")
            return
        }
        
        // Get user data before deletion
        guard let currentAppUser = self.currentUser else {
            completion(false, "User data not found")
            return
        }
        
        let dbRef = Database.database().reference()
        
        // Step 1: Get Apple ID for auth mapping cleanup
        var appleId: String?
        for provider in user.providerData {
            if provider.providerID == "apple.com" {
                appleId = provider.uid
                break
            }
        }
        
        // Step 2: Delete user data from Firebase
        let userIdString = currentAppUser.uid
        
        // Delete user from Firebase Realtime Database
        dbRef.child("users").child(userIdString).removeValue { error, _ in
            if let error = error {
                print("Error deleting user data: \(error.localizedDescription)")
                completion(false, "Failed to delete user data: \(error.localizedDescription)")
                return
            }
            
            // Delete auth mapping if Apple ID exists
            if let appleUserId = appleId {
                let encodedAppleId = self.encodeForFirebase(appleUserId)
                dbRef.child("auth_mapping").child(encodedAppleId).removeValue()
            }
            
            // Step 3: Delete Firebase Auth account
            user.delete { error in
                if let error = error {
                    print("Error deleting Firebase Auth account: \(error.localizedDescription)")
                    completion(false, "Failed to delete account: \(error.localizedDescription)")
                } else {
                    // Step 4: Clear local data
                    self.signOut()
                    
                    // Clear UserDefaults
                    UserDefaults.standard.removeObject(forKey: "currentUserId")
                    UserDefaults.standard.removeObject(forKey: "currentRoomId")
                    UserDefaults.standard.removeObject(forKey: "hasAcceptedPrivacyPolicy")
                    UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
                    
                    print("Account successfully deleted")
                    completion(true, nil)
                }
            }
        }
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
