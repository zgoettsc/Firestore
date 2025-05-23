import StoreKit
import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore
import SwiftUI
import RevenueCat

enum SubscriptionPlan: String, CaseIterable {
    case none = "none"
    case plan1Room = "com.zthreesolutions.tolerancetracker.room01"
    case plan2Rooms = "com.zthreesolutions.tolerancetracker.room02"
    case plan3Rooms = "com.zthreesolutions.tolerancetracker.room03"
    case plan4Rooms = "com.zthreesolutions.tolerancetracker.room04"
    case plan5Rooms = "com.zthreesolutions.tolerancetracker.room05"
    
    init(productID: String) {
        switch productID {
        case "com.zthreesolutions.tolerancetracker.room01": self = .plan1Room
        case "com.zthreesolutions.tolerancetracker.room02": self = .plan2Rooms
        case "com.zthreesolutions.tolerancetracker.room03": self = .plan3Rooms
        case "com.zthreesolutions.tolerancetracker.room04": self = .plan4Rooms
        case "com.zthreesolutions.tolerancetracker.room05": self = .plan5Rooms
        default: self = .none
        }
    }
    
    var roomLimit: Int {
        switch self {
        case .none: return 0
        case .plan1Room: return 1
        case .plan2Rooms: return 2
        case .plan3Rooms: return 3
        case .plan4Rooms: return 4
        case .plan5Rooms: return 5
        }
    }
    
    var displayName: String {
        switch self {
        case .none: return "No Subscription"
        case .plan1Room: return "1 Room Plan"
        case .plan2Rooms: return "2 Room Plan"
        case .plan3Rooms: return "3 Room Plan"
        case .plan4Rooms: return "4 Room Plan"
        case .plan5Rooms: return "5 Room Plan"
        }
    }
    
    var monthlyPrice: String {
        switch self {
        case .none: return "$0"
        case .plan1Room: return "$9.99"
        case .plan2Rooms: return "$19.98"
        case .plan3Rooms: return "$29.97"
        case .plan4Rooms: return "$39.96"
        case .plan5Rooms: return "$49.95"
        }
    }
}

class StoreManager: NSObject, ObservableObject {
    @Published var offerings: Offerings?
    @Published var currentSubscriptionPlan: SubscriptionPlan = .none
    @Published var isLoading = false
    @Published var hasActiveSubscription = false
    
    static let shared = StoreManager()
    
    private var currentAppData: AppData?
    private let firestore = Firestore.firestore()
    
    func setAppData(_ appData: AppData) {
        currentAppData = appData
    }
    
    private func getCurrentAppData() -> AppData? {
        return currentAppData
    }
    
    override init() {
        super.init()
        
        if Purchases.isConfigured == false {
            Purchases.configure(withAPIKey: "appl_xbvOWCkQEhgewsiKrzHbicOCOOd")
        }
        
        Purchases.shared.delegate = self
        setupFirestoreListener()
    }
    
    func loadOfferings() {
        isLoading = true
        
        Purchases.shared.getOfferings { [weak self] offerings, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    print("Error loading offerings: \(error.localizedDescription)")
                    return
                }
                
                self?.offerings = offerings
                print("Loaded offerings successfully")
            }
        }
    }
    
    // Setup Firestore listener for subscription changes
    private func setupFirestoreListener() {
        guard let authUser = Auth.auth().currentUser else { return }
        
        // Listen to the customer document created by the RevenueCat extension
        firestore.collection("customers").document(authUser.uid)
            .addSnapshotListener { [weak self] documentSnapshot, error in
                if let error = error {
                    print("Error listening to customer document: \(error)")
                    return
                }
                
                guard let document = documentSnapshot, document.exists,
                      let data = document.data() else {
                    print("Customer document doesn't exist yet")
                    return
                }
                
                self?.processFirestoreSubscriptionData(data)
            }
    }
    
    private func processFirestoreSubscriptionData(_ data: [String: Any]) {
        // The RevenueCat extension stores entitlements in the customer document
        guard let entitlements = data["entitlements"] as? [String: Any] else {
            print("No entitlements found in customer document")
            currentSubscriptionPlan = .none
            hasActiveSubscription = false
            updateAppDataSubscription(plan: .none)
            return
        }
        
        // Check for active entitlements
        var activePlan: SubscriptionPlan = .none
        
        for (entitlementId, entitlementData) in entitlements {
            guard let entitlement = entitlementData as? [String: Any],
                  let isActive = entitlement["is_active"] as? Bool,
                  isActive else { continue }
            
            // Map entitlement IDs to subscription plans
            switch entitlementId {
            case "5_room_access": activePlan = .plan5Rooms
            case "4_room_access": activePlan = .plan4Rooms
            case "3_room_access": activePlan = .plan3Rooms
            case "2_room_access": activePlan = .plan2Rooms
            case "1_room_access": activePlan = .plan1Room
            default: continue
            }
            
            // Use the highest tier plan if multiple are active
            if activePlan.roomLimit > currentSubscriptionPlan.roomLimit {
                break
            }
        }
        
        let wasActive = hasActiveSubscription
        currentSubscriptionPlan = activePlan
        hasActiveSubscription = activePlan != .none
        
        print("Updated subscription from Firestore: \(activePlan.displayName)")
        
        // Handle subscription changes
        if wasActive && !hasActiveSubscription {
            handleSubscriptionCancellation()
        } else if !wasActive && hasActiveSubscription {
            clearGracePeriod()
        }
        
        updateAppDataSubscription(plan: activePlan)
    }
    
    private func updateAppDataSubscription(plan: SubscriptionPlan) {
        guard let appData = getCurrentAppData(),
              let currentUser = appData.currentUser else { return }
        
        // Update Firebase Realtime Database
        let dbRef = Database.database().reference()
        let userId = currentUser.id.uuidString
        
        let updates: [String: Any] = [
            "subscriptionPlan": plan.rawValue,
            "roomLimit": plan.roomLimit
        ]
        
        dbRef.child("users").child(userId).updateChildValues(updates) { error, _ in
            if let error = error {
                print("Error updating subscription in Realtime Database: \(error)")
            } else {
                print("Successfully updated subscription in Realtime Database")
                
                DispatchQueue.main.async {
                    // Update local app state
                    var updatedUser = currentUser
                    updatedUser.subscriptionPlan = plan.rawValue
                    updatedUser.roomLimit = plan.roomLimit
                    appData.currentUser = updatedUser
                    
                    // Notify views
                    NotificationCenter.default.post(
                        name: Notification.Name("SubscriptionUpdated"),
                        object: nil,
                        userInfo: [
                            "plan": plan.rawValue,
                            "limit": plan.roomLimit,
                            "userIdString": userId
                        ]
                    )
                }
            }
        }
    }
    
    func checkSubscriptionStatus() {
        // With the Firebase extension, we rely on the Firestore listener
        // But we can still manually check RevenueCat if needed
        Purchases.shared.getCustomerInfo { [weak self] customerInfo, error in
            if let error = error {
                print("Error getting customer info: \(error.localizedDescription)")
                return
            }
            
            guard let customerInfo = customerInfo else { return }
            
            // The extension will handle updating Firestore, but we can log here
            print("Manual check - Active entitlements: \(customerInfo.entitlements.active.keys)")
        }
    }
    
    func purchasePackage(_ package: Package, appData: AppData, completion: @escaping (Bool, String?) -> Void) {
        let newPlan = SubscriptionPlan(productID: package.storeProduct.productIdentifier)
        let currentRoomCount = appData.currentUser?.ownedRooms?.count ?? 0
        
        // Check if this is a downgrade that would exceed room limit
        if newPlan.roomLimit < currentRoomCount {
            let roomsToDelete = currentRoomCount - newPlan.roomLimit
            completion(false, "You currently own \(currentRoomCount) rooms but the \(newPlan.displayName) only allows \(newPlan.roomLimit). Please delete \(roomsToDelete) room\(roomsToDelete > 1 ? "s" : "") before downgrading.")
            return
        }
        
        isLoading = true
        
        Purchases.shared.purchase(package: package) { [weak self] transaction, customerInfo, error, userCancelled in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if userCancelled {
                    completion(false, "Purchase cancelled by user")
                    return
                }
                
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                
                // Success - the Firebase extension will automatically update Firestore
                // and our listener will pick up the changes
                print("Purchase successful - waiting for Firebase extension to sync data")
                completion(true, nil)
            }
        }
    }
    
    private func handleSubscriptionCancellation() {
        guard let appData = getCurrentAppData(),
              let currentUser = appData.currentUser else { return }
        
        print("Subscription cancelled, setting grace period")
        
        let userId = currentUser.id.uuidString
        let dbRef = Database.database().reference()
        
        // Set grace period end date (2 weeks from now)
        let gracePeriodEnd = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        
        let updates: [String: Any] = [
            "subscriptionGracePeriodEnd": ISO8601DateFormatter().string(from: gracePeriodEnd),
            "isInGracePeriod": true
        ]
        
        dbRef.child("users").child(userId).updateChildValues(updates) { error, _ in
            if let error = error {
                print("Error setting grace period: \(error.localizedDescription)")
            } else {
                print("Successfully set grace period until: \(gracePeriodEnd)")
                
                DispatchQueue.main.async {
                    appData.subscriptionGracePeriodEnd = gracePeriodEnd
                    appData.isInGracePeriod = true
                    appData.objectWillChange.send()
                    
                    // Schedule grace period check
                    self.scheduleGracePeriodCheck(appData: appData)
                    
                    // Show cancellation notification
                    NotificationCenter.default.post(
                        name: Notification.Name("SubscriptionCancelled"),
                        object: nil,
                        userInfo: [
                            "gracePeriodEnd": gracePeriodEnd,
                            "roomCount": currentUser.ownedRooms?.count ?? 0
                        ]
                    )
                }
            }
        }
    }
    
    private func clearGracePeriod() {
        guard let appData = getCurrentAppData(),
              let user = appData.currentUser else { return }
        
        let dbRef = Database.database().reference()
        let userId = user.id.uuidString
        
        let updates: [String: Any] = [
            "subscriptionGracePeriodEnd": NSNull(),
            "isInGracePeriod": false
        ]
        
        dbRef.child("users").child(userId).updateChildValues(updates) { error, _ in
            if let error = error {
                print("Error clearing grace period: \(error.localizedDescription)")
            } else {
                print("Successfully cleared grace period - user resubscribed")
                
                DispatchQueue.main.async {
                    appData.subscriptionGracePeriodEnd = nil
                    appData.isInGracePeriod = false
                    appData.objectWillChange.send()
                    
                    NotificationCenter.default.post(
                        name: Notification.Name("SubscriptionReactivated"),
                        object: nil
                    )
                }
            }
        }
    }
    
    private func scheduleGracePeriodCheck(appData: AppData) {
        guard let gracePeriodEnd = appData.subscriptionGracePeriodEnd else { return }
        
        let timeUntilEnd = gracePeriodEnd.timeIntervalSinceNow
        
        if timeUntilEnd > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeUntilEnd) {
                self.checkGracePeriodExpiry(appData: appData)
            }
        } else {
            checkGracePeriodExpiry(appData: appData)
        }
    }
    
    private func checkGracePeriodExpiry(appData: AppData) {
        // Check if user has resubscribed
        if !hasActiveSubscription {
            removeAllUserRooms(appData: appData)
        }
    }
    
    private func removeAllUserRooms(appData: AppData) {
        guard let currentUser = appData.currentUser,
              let ownedRooms = currentUser.ownedRooms else { return }
        
        let userId = currentUser.id.uuidString
        let dbRef = Database.database().reference()
        
        print("Grace period expired, deleting \(ownedRooms.count) rooms")
        
        // Delete all owned rooms
        for roomId in ownedRooms {
            appData.deleteRoom(roomId: roomId) { success, error in
                if let error = error {
                    print("Error deleting room \(roomId): \(error)")
                }
            }
        }
        
        // Clear grace period and reset subscription
        let updates: [String: Any] = [
            "subscriptionPlan": SubscriptionPlan.none.rawValue,
            "roomLimit": 0,
            "ownedRooms": NSNull(),
            "subscriptionGracePeriodEnd": NSNull(),
            "isInGracePeriod": false
        ]
        
        dbRef.child("users").child(userId).updateChildValues(updates) { error, _ in
            if let error = error {
                print("Error clearing subscription data: \(error.localizedDescription)")
            } else {
                print("Successfully cleared subscription data after grace period")
                
                DispatchQueue.main.async {
                    var updatedUser = currentUser
                    updatedUser.subscriptionPlan = SubscriptionPlan.none.rawValue
                    updatedUser.roomLimit = 0
                    updatedUser.ownedRooms = nil
                    appData.currentUser = updatedUser
                    appData.subscriptionGracePeriodEnd = nil
                    appData.isInGracePeriod = false
                    appData.objectWillChange.send()
                    
                    NotificationCenter.default.post(
                        name: Notification.Name("RoomsDeletedAfterGracePeriod"),
                        object: nil
                    )
                }
            }
        }
    }
    
    func restorePurchases(completion: @escaping (Bool, String?) -> Void) {
        isLoading = true
        
        Purchases.shared.restorePurchases { [weak self] customerInfo, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                
                if customerInfo != nil {
                    // The Firebase extension will handle updating Firestore
                    completion(true, nil)
                } else {
                    completion(false, "No purchases to restore")
                }
            }
        }
    }
    
    func manageSubscriptions() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Debug Testing Methods
    
#if DEBUG
    func debugAppDataState() {
        if let appData = getCurrentAppData() {
            print("🚨 DEBUG AppData State:")
            print("  - isInGracePeriod: \(appData.isInGracePeriod)")
            print("  - subscriptionGracePeriodEnd: \(String(describing: appData.subscriptionGracePeriodEnd))")
            print("  - current user: \(appData.currentUser?.name ?? "nil")")
            print("  - owned rooms: \(appData.currentUser?.ownedRooms?.count ?? 0)")
        } else {
            print("🚨 DEBUG: No AppData available")
        }
    }
    
    func forceUIRefresh() {
        if let appData = getCurrentAppData() {
            DispatchQueue.main.async {
                appData.objectWillChange.send()
                print("🚨 DEBUG: Forced UI refresh")
            }
        }
    }
    
    func simulateCancellation() {
        print("🚨 DEBUG: Simulating subscription cancellation")
        let wasActive = hasActiveSubscription
        
        hasActiveSubscription = false
        currentSubscriptionPlan = .none
        
        if wasActive && !hasActiveSubscription {
            handleSubscriptionCancellation()
        }
    }
    
    func simulateReactivation() {
        print("🚨 DEBUG: Simulating subscription reactivation")
        hasActiveSubscription = true
        currentSubscriptionPlan = .plan1Room
        
        clearGracePeriod()
        updateAppDataSubscription(plan: currentSubscriptionPlan)
    }
#endif
}

// MARK: - PurchasesDelegate
extension StoreManager: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        print("RevenueCat delegate: Customer info updated")
        // The Firebase extension will handle the data sync automatically
        // We just log that we received the update
    }
}
