import SwiftUI
import RevenueCat

struct SubscriptionManagementView: View {
    @ObservedObject var appData: AppData
    @StateObject private var storeManager = StoreManager.shared
    @State private var selectedPackage: Package?
    @State private var showingPurchaseConfirmation = false
    @State private var errorMessage: String?
    @State private var showError = false
    @Environment(\.dismiss) var dismiss
    
    private var currentPlan: SubscriptionPlan {
        // If in grace period, show no subscription
        if appData.isInGracePeriod {
            return .none
        }
        
        if let plan = appData.currentUser?.subscriptionPlan {
            return SubscriptionPlan(productID: plan)
        }
        return .none
    }
    
    private var currentRoomCount: Int {
        return appData.currentUser?.ownedRooms?.count ?? 0
    }
    
    private var roomLimit: Int {
        // If in grace period, show 0 room limit
        if appData.isInGracePeriod {
            return 0
        }
        
        return appData.currentUser?.roomLimit ?? 0
    }
    
    var body: some View {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Current Plan Status
                    currentPlanSection
                    
                    // Available Plans
                    availablePlansSection
                    
                    // Action Buttons
                    actionButtonsSection
                }
                .padding()
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.large)
          //  .navigationBarItems(
           //       leading: Button("Cancel") { dismiss() },
          //      trailing: Button("Done") { dismiss() }
           // )
        
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                showError = false
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .confirmationDialog("Confirm Purchase", isPresented: $showingPurchaseConfirmation) {
            Button("Purchase") {
                if let package = selectedPackage {
                    purchasePackage(package)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let package = selectedPackage {
                Text("Purchase \(SubscriptionPlan(productID: package.storeProduct.productIdentifier).displayName) for \(package.localizedPriceString)?")
            }
        }
        .onAppear {
            storeManager.setAppData(appData)
            storeManager.loadOfferings()
            refreshUserData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SubscriptionUpdated"))) { _ in
            refreshUserData()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Room Subscriptions")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Choose the number of rooms you need")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var currentPlanSection: some View {
        VStack(spacing: 16) {
            Text("Current Plan")
                .font(.headline)
            
            VStack(spacing: 12) {
                Text(currentPlan.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if currentPlan != .none {
                    HStack {
                        Text("Rooms: \(currentRoomCount)/\(roomLimit)")
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(roomUsageColor.opacity(0.2))
                            )
                            .foregroundColor(roomUsageColor)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
    
    private var roomUsageColor: Color {
        if roomLimit == 0 { return .gray }
        return currentRoomCount >= roomLimit ? .orange : .green
    }
    
    private var availablePlansSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Available Plans")
                .font(.headline)
            
            if storeManager.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading plans...")
                    Spacer()
                }
                .padding()
            } else if let packages = storeManager.offerings?.current?.availablePackages {
                LazyVStack(spacing: 12) {
                    ForEach(SubscriptionPlan.allCases.filter { $0 != .none }, id: \.self) { plan in
                        if let package = packages.first(where: { SubscriptionPlan(productID: $0.storeProduct.productIdentifier) == plan }) {
                            PlanRowView(
                                plan: plan,
                                package: package,
                                isCurrentPlan: plan == currentPlan,
                                currentRoomCount: currentRoomCount,
                                isProcessing: storeManager.isLoading
                            ) {
                                selectedPackage = package
                                showingPurchaseConfirmation = true
                            }
                        }
                    }
                }
            } else {
                Text("No subscription plans available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button("Restore Purchases") {
                storeManager.restorePurchases { success, error in
                    if !success, let error = error {
                        errorMessage = error
                        showError = true
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(storeManager.isLoading)
            
            Button("Manage in App Store") {
                storeManager.manageSubscriptions()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray5))
            .foregroundColor(.primary)
            .cornerRadius(12)
            
#if DEBUG
// Debug Testing Buttons
VStack(spacing: 8) {
    Text("🚨 DEBUG TESTING")
        .font(.caption)
        .foregroundColor(.red)
    
    Button("Sync AppData") {
           syncAppDataWithStoreManager()
       }
       .frame(maxWidth: .infinity)
       .padding()
       .background(Color.purple)
       .foregroundColor(.white)
       .cornerRadius(12)
       
       Button("Check AppData State") {
           StoreManager.shared.debugAppDataState()
       }
       .frame(maxWidth: .infinity)
       .padding()
       .background(Color.gray)
       .foregroundColor(.white)
       .cornerRadius(12)
    
    Button("Simulate Cancellation") {
        StoreManager.shared.simulateCancellation()
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color.red)
    .foregroundColor(.white)
    .cornerRadius(12)
    
    Button("Simulate Reactivation") {
        StoreManager.shared.simulateReactivation()
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color.green)
    .foregroundColor(.white)
    .cornerRadius(12)
    
    Button("Force UI Refresh") {
        StoreManager.shared.forceUIRefresh()
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color.purple)
    .foregroundColor(.white)
    .cornerRadius(12)
}
#endif
        }
    }
    
    private func purchasePackage(_ package: Package) {
        storeManager.purchasePackage(package, appData: appData) { success, error in
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    refreshUserData()
                    dismiss()
                }
            } else if let error = error {
                errorMessage = error
                showError = true
            }
        }
    }
    
    private func syncAppDataWithStoreManager() {
        // Force the StoreManager to use THIS AppData instance
        StoreManager.shared.setAppData(appData)
        
        // Also manually trigger any needed updates
        appData.forceRefreshCurrentUser {
            print("🚨 DEBUG: Force refreshed current user in SubscriptionManagementView")
        }
    }
    
    private func refreshUserData() {
        appData.forceRefreshCurrentUser {
            // Data refreshed
        }
    }
}
