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
    private var firestoreListener: ListenerRegistration?
    
    func setAppData(_ appData: AppData) {
        currentAppData = appData
        print("🚨 DEBUG: StoreManager appData set, starting subscription monitoring")
        setupSubscriptionMonitoring()
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
    
    // Setup comprehensive subscription monitoring
    private func setupSubscriptionMonitoring() {
        // Only listen to RevenueCat - it's the source of truth
        setupRevenueCatListener()
        print("🚨 StoreManager: Using RevenueCat as single source of truth")
    }
    
    private func setupRevenueCatListener() {
        // Get current subscription status from RevenueCat
        Purchases.shared.getCustomerInfo { [weak self] customerInfo, error in
            if let error = error {
                print("Error getting RevenueCat customer info: \(error.localizedDescription)")
                return
            }
            
            guard let customerInfo = customerInfo else { return }
            
            print("RevenueCat customer info: Active entitlements: \(customerInfo.entitlements.active.keys)")
            
            // Process the subscription data
            self?.processRevenueCatData(customerInfo)
        }
    }
    
    private func processRevenueCatData(_ customerInfo: CustomerInfo) {
        print("🚨 Processing RevenueCat entitlements")
        print("🚨 Active entitlements: \(customerInfo.entitlements.active.keys)")
        print("🚨 All entitlements: \(customerInfo.entitlements.all.keys)")
        
        var activePlan: SubscriptionPlan = .none
        var mostRecentDate: Date?
        var mostRecentAction = "none"
        
        // Check ALL entitlements (active and inactive) to find the most recent event
        for (entitlementId, entitlement) in customerInfo.entitlements.all {
            print("🚨 Checking entitlement: \(entitlementId)")
            print("🚨   isActive: \(entitlement.isActive)")
            print("🚨   latestPurchaseDate: \(entitlement.latestPurchaseDate)")
            print("🚨   expirationDate: \(entitlement.expirationDate?.description ?? "none")")
            
            // Map entitlement IDs to subscription plans
            let plan: SubscriptionPlan
            switch entitlementId {
            case "5_room_access": plan = .plan5Rooms
            case "4_room_access": plan = .plan4Rooms
            case "3_room_access": plan = .plan3Rooms
            case "2_room_access": plan = .plan2Rooms
            case "1_room_access": plan = .plan1Room
            default:
                print("🚨   Unknown entitlement: \(entitlementId)")
                continue
            }
            
            if entitlement.isActive {
                // Active subscription - use purchase date (if available)
                guard let entitlementDate = entitlement.latestPurchaseDate else {
                    print("🚨   Skipping active entitlement with no purchase date: \(entitlementId)")
                    continue
                }
                
                if let currentMostRecent = mostRecentDate {
                    if entitlementDate > currentMostRecent {
                        mostRecentDate = entitlementDate
                        activePlan = plan
                        mostRecentAction = "purchased/renewed"
                        print("🚨   New most recent ACTIVE plan: \(plan.displayName) (purchased: \(entitlementDate))")
                    }
                } else {
                    // No previous date, so this purchase is the most recent
                    mostRecentDate = entitlementDate
                    activePlan = plan
                    mostRecentAction = "purchased/renewed"
                    print("🚨   New most recent ACTIVE plan: \(plan.displayName) (purchased: \(entitlementDate))")
                }
            } else if let expirationDate = entitlement.expirationDate {
                // Inactive/expired subscription - use expiration date as cancellation date
                if let currentMostRecent = mostRecentDate {
                    if expirationDate > currentMostRecent {
                        mostRecentDate = expirationDate
                        activePlan = .none // Cancellation means no active plan
                        mostRecentAction = "cancelled/expired"
                        print("🚨   New most recent CANCELLATION: \(plan.displayName) (expired: \(expirationDate))")
                    }
                } else {
                    // No previous date, so this expiration is the most recent
                    mostRecentDate = expirationDate
                    activePlan = .none
                    mostRecentAction = "cancelled/expired"
                    print("🚨   New most recent CANCELLATION: \(plan.displayName) (expired: \(expirationDate))")
                }
            }
        }
        
        print("🚨 Final result: \(activePlan.displayName)")
        print("🚨 Most recent action: \(mostRecentAction) on \(mostRecentDate?.description ?? "none")")
        
        // Update subscription immediately
        updateSubscription(to: activePlan)
    }
    
    private func setupFirestoreListener() {
        // DISABLED: Firestore listener causes conflicts with RevenueCat
        // RevenueCat is the single source of truth for subscription status
        print("🚨 Firestore listener disabled - using RevenueCat as single source of truth")
    }
    
    // REMOVED: processFirestoreSubscriptionData - no longer needed since we use RevenueCat as single source of truth
    
    private func updateSubscription(to plan: SubscriptionPlan) {
        let wasActive = hasActiveSubscription
        
        DispatchQueue.main.async {
            self.currentSubscriptionPlan = plan
            self.hasActiveSubscription = plan != .none
            
            print("🚨 StoreManager: Updated subscription to \(plan.displayName), active: \(self.hasActiveSubscription)")
        }
        
        // Handle subscription changes
        if wasActive && !hasActiveSubscription {
            handleSubscriptionCancellation()
        } else if !wasActive && hasActiveSubscription {
            clearGracePeriod()
        }
        
        // Update app data and Firebase Realtime Database
        updateAppDataSubscription(plan: plan)
    }
    
    private func updateAppDataSubscription(plan: SubscriptionPlan) {
        guard let appData = getCurrentAppData(),
              let currentUser = appData.currentUser else {
            print("🚨 ERROR: No app data or current user available for subscription update")
            return
        }
        
        let userId = currentUser.id.uuidString
        
        print("🚨 DEBUG: Starting subscription update")
        print("  - Current plan in AppData: \(currentUser.subscriptionPlan ?? "nil")")
        print("  - Current limit in AppData: \(currentUser.roomLimit)")
        print("  - New plan: \(plan.rawValue)")
        print("  - New limit: \(plan.roomLimit)")
        
        // Update local app state FIRST for immediate UI response
        DispatchQueue.main.async {
            var updatedUser = currentUser
            updatedUser.subscriptionPlan = plan.rawValue
            updatedUser.roomLimit = plan.roomLimit
            appData.currentUser = updatedUser
            appData.objectWillChange.send()
            
            print("🚨 IMMEDIATE: Updated AppData user subscription to \(plan.displayName)")
            print("🚨 IMMEDIATE: AppData now shows plan: \(updatedUser.subscriptionPlan ?? "nil"), limit: \(updatedUser.roomLimit)")
            
            // Post immediate notification
            NotificationCenter.default.post(
                name: Notification.Name("SubscriptionUpdated"),
                object: nil,
                userInfo: [
                    "plan": plan.rawValue,
                    "limit": plan.roomLimit,
                    "userIdString": userId
                ]
            )
            
            print("🚨 IMMEDIATE: Posted SubscriptionUpdated notification")
        }
        
        // Then update Firebase as a backup
        let dbRef = Database.database().reference()
        let updates: [String: Any] = [
            "subscriptionPlan": plan.rawValue,
            "roomLimit": plan.roomLimit
        ]
        
        print("🚨 FIREBASE: Updating Realtime Database for user \(userId): \(updates)")
        
        dbRef.child("users").child(userId).updateChildValues(updates) { error, _ in
            if let error = error {
                print("🚨 ERROR: Failed to update Firebase: \(error)")
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name("SubscriptionUpdateFailed"),
                        object: nil,
                        userInfo: ["error": error.localizedDescription]
                    )
                }
            } else {
                print("🚨 FIREBASE: Successfully updated subscription in Realtime Database")
            }
        }
    }
    
    func checkSubscriptionStatus() {
        print("🚨 Manual subscription status check")
        
        // Check RevenueCat first
        Purchases.shared.getCustomerInfo { [weak self] customerInfo, error in
            if let error = error {
                print("Error getting customer info: \(error.localizedDescription)")
                return
            }
            
            guard let customerInfo = customerInfo else { return }
            
            print("Manual check - Active entitlements: \(customerInfo.entitlements.active.keys)")
            self?.processRevenueCatData(customerInfo)
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
                
                print("Purchase successful - processing subscription update")
                
                // Process the updated customer info immediately
                if let customerInfo = customerInfo {
                    self?.processRevenueCatData(customerInfo)
                }
                
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
                
                if let customerInfo = customerInfo {
                    // Process the restored subscription data
                    self?.processRevenueCatData(customerInfo)
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
    
    deinit {
        firestoreListener?.remove()
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
            print("  - subscription plan: \(appData.currentUser?.subscriptionPlan ?? "nil")")
            print("  - room limit: \(appData.currentUser?.roomLimit ?? 0)")
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
        updateSubscription(to: .none)
    }
    
    func simulateReactivation() {
        print("🚨 DEBUG: Simulating subscription reactivation")
        updateSubscription(to: .plan1Room)
    }
#endif
}

// MARK: - PurchasesDelegate
extension StoreManager: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        print("🚨 RevenueCat delegate: Customer info updated")
        print("Active entitlements: \(customerInfo.entitlements.active.keys)")
        
        // Process the updated customer info immediately
        processRevenueCatData(customerInfo)
    }
}
