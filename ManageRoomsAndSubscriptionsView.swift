import SwiftUI
import FirebaseAuth
import FirebaseDatabase
import RevenueCat

struct ManageRoomsAndSubscriptionsView: View {
    @ObservedObject var appData: AppData
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var storeManager = StoreManager.shared
    @State private var availableRooms: [String: (String, Bool)] = [:] // [roomId: (name, isOwned)]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingJoinRoom = false
    @State private var showingCreateRoom = false
    @State private var showingSubscriptionView = false
    @State private var currentRoomName: String = "Loading..."
    @State private var isSwitching = false
    @State private var roomToDelete: String? = nil
    @State private var roomToLeave: String? = nil
    @State private var showingDeleteAlert = false
    @State private var showingLeaveAlert = false
    @State private var showingLimitReachedAlert = false
    @State private var selectedPackage: Package?
    @State private var showingPurchaseConfirmation = false
    @State private var showError = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) var dismiss
    
    private var subscriptionPlan: SubscriptionPlan {
        // If in grace period, show no subscription
        if appData.isInGracePeriod {
            return .none
        }
        
        if let plan = appData.currentUser?.subscriptionPlan {
            return SubscriptionPlan(productID: plan)
        }
        return .none
    }
    
    private var roomLimit: Int {
        // If in grace period, show 0 room limit
        if appData.isInGracePeriod {
            return 0
        }
        
        return appData.currentUser?.roomLimit ?? 0
    }
    
    private var ownedRoomCount: Int {
        return appData.currentUser?.ownedRooms?.count ?? 0
    }
    
    private var canCreateRoom: Bool {
        return ownedRoomCount < roomLimit
    }
    
    // Colors that adapt to light/dark mode
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(UIColor.systemBackground)
    }
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.2) : Color(UIColor.secondarySystemBackground)
    }
    
    private var textColor: Color {
        colorScheme == .dark ? Color.white : Color.primary
    }
    
    private var subtitleColor: Color {
        colorScheme == .dark ? Color.gray : Color.secondary
    }
    
    var body: some View {
        ZStack {
            backgroundColor.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Title
                    Text("Rooms and Subscription")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(textColor)
                        .padding(.top, 20)
                    
                    // Subscription Status Section
                    subscriptionStatusSection
                    
                    // Current Room Section (only if there's a current room)
                    if let roomId = appData.currentRoomId, !roomId.isEmpty {
                        currentRoomSection(roomId: roomId)
                    }
                    
                    // Other Available Rooms
                    otherRoomsSection
                    
                    // Action Buttons
                    actionButtonsSection
                    
                    
                    // Footer Links
                    footerSection
                }
            }
            
            if isSwitching {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    ProgressView()
                    Text("Switching Room...")
                        .foregroundColor(.white)
                        .padding(.top, 10)
                }
                .padding(20)
                .background(Color(UIColor.systemGray5))
                .cornerRadius(10)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCurrentRoomName()
            loadAvailableRooms()
            loadUserSubscriptionStatus()
            storeManager.loadOfferings()
        }
        .sheet(isPresented: $showingJoinRoom) {
            JoinRoomView(appData: appData)
                .onDisappear {
                    loadAvailableRooms()
                }
        }
        .sheet(isPresented: $showingCreateRoom) {
            CreateRoomView(appData: appData)
                .environmentObject(authViewModel)
                .onDisappear {
                    loadAvailableRooms()
                }
        }
        .sheet(isPresented: $showingSubscriptionView) {
            NavigationView {
                SubscriptionManagementView(appData: appData)
                    .navigationBarItems(trailing: Button("Done") {
                        showingSubscriptionView = false
                    })
            }
            .onDisappear {
                loadUserSubscriptionStatus()
                loadAvailableRooms()
            }
        }
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
        .alert(isPresented: $showingDeleteAlert) {
            Alert(
                title: Text("Delete Room"),
                message: Text("Are you sure you want to delete this room?"),
                primaryButton: .destructive(Text("Delete")) {
                    if let roomId = roomToDelete {
                        deleteRoom(roomId: roomId)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showingLeaveAlert) {
            Alert(
                title: Text("Leave Room"),
                message: Text("Are you sure you want to leave this room? You will no longer have access to the room data."),
                primaryButton: .destructive(Text("Leave")) {
                    if let roomId = roomToLeave {
                        leaveRoom(roomId: roomId)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showingLimitReachedAlert) {
            Alert(
                title: Text("Room Limit Reached"),
                message: Text("You have reached the maximum number of rooms allowed in your current subscription plan. Please upgrade your subscription to create more rooms."),
                primaryButton: .default(Text("Upgrade")) {
                    showingSubscriptionView = true
                },
                secondaryButton: .cancel()
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SubscriptionUpdated"))) { notification in
            print("ManageRoomsView: Received SubscriptionUpdated notification")
            
            // Update local state immediately
            if let userInfo = notification.userInfo,
               let plan = userInfo["plan"] as? String,
               let limit = userInfo["limit"] as? Int,
               let userIdString = userInfo["userIdString"] as? String,
               userIdString == appData.currentUser?.id.uuidString {
                var updatedUser = appData.currentUser
                updatedUser?.subscriptionPlan = plan
                updatedUser?.roomLimit = limit
                appData.currentUser = updatedUser
                appData.objectWillChange.send()
            }
            
            // Fetch latest data
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.loadUserSubscriptionStatus()
                self.loadAvailableRooms()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SubscriptionUpdateFailed"))) { notification in
            print("ManageRoomsView: Received SubscriptionUpdateFailed notification")
            if let userInfo = notification.userInfo, let error = userInfo["error"] as? String {
                errorMessage = error
                isLoading = false
                showError = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserDataRefreshed"))) { _ in
            print("ManageRoomsView: Received UserDataRefreshed notification")
            refreshUserDataFromAppleAuth()  // Use the new method
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RoomLeft"))) { _ in
            loadAvailableRooms()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RoomDeleted"))) { _ in
            loadAvailableRooms()
            loadUserSubscriptionStatus()
        }
    }
    
    // MARK: - View Sections
    
    private var subscriptionStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SUBSCRIPTION STATUS")
                .font(.headline)
                .foregroundColor(subtitleColor)
                .padding(.leading)
            
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subscriptionPlan.displayName)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("\(ownedRoomCount) of \(roomLimit) rooms in use")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        showingSubscriptionView = true
                    }) {
                        Text("Manage")
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                
                // Progress bar
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 10)
                                .cornerRadius(5)
                            
                            Rectangle()
                                .fill(roomLimit > 0 ? (ownedRoomCount >= roomLimit ? Color.orange : Color.blue) : Color.gray)
                                .frame(width: roomLimit > 0 ? min(CGFloat(ownedRoomCount) / CGFloat(roomLimit) * geometry.size.width, geometry.size.width) : 0, height: 10)
                                .cornerRadius(5)
                        }
                    }
                    .frame(height: 10)
                }
            }
            .padding()
            .background(cardBackgroundColor)
            .cornerRadius(10)
        }
        .padding(.horizontal)
    }
    
    private func currentRoomSection(roomId: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CURRENT ROOM")
                .font(.headline)
                .foregroundColor(subtitleColor)
                .padding(.leading)
            
            let isOwned = appData.currentUser?.ownedRooms?.contains(roomId) ?? false
            
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.green, lineWidth: 2)
                    )
                
                VStack(spacing: 4) {
                    RoomEntryView(roomId: roomId, roomName: currentRoomName, appData: appData)
                        .padding()
                        .background(Color.clear)
                        .cornerRadius(10)
                    
                    // Status indicators
                    HStack {
                        Text(isOwned ? "Owner" : "Invited")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isOwned ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                            .foregroundColor(isOwned ? .blue : .orange)
                            .cornerRadius(8)
                        
                        // Grace period indicator for owned rooms
                        if isOwned && appData.isInGracePeriod, let gracePeriodEnd = appData.subscriptionGracePeriodEnd {
                            let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: gracePeriodEnd).day ?? 0
                            
                            Text("⚠️ \(daysRemaining)d left")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                        }
                        
                        Spacer()
                        
                        Text("Active")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var otherRoomsSection: some View {
        Group {
            if !availableRooms.filter({ $0.key != appData.currentRoomId }).isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("OTHER ROOMS")
                        .font(.headline)
                        .foregroundColor(subtitleColor)
                        .padding(.leading)
                    
                    ForEach(Array(availableRooms.keys.sorted()), id: \.self) { roomId in
                        if roomId != appData.currentRoomId {
                            let roomInfo = availableRooms[roomId]!
                            let roomName = roomInfo.0
                            let isOwned = roomInfo.1
                            
                            VStack(spacing: 4) {
                                RoomEntryView(roomId: roomId, roomName: roomName, appData: appData)
                                    .padding()
                                    .background(cardBackgroundColor)
                                    .cornerRadius(10)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        switchToRoom(roomId: roomId)
                                    }
                                
                                // Status indicators
                                HStack {
                                    Text(isOwned ? "Owner" : "Invited")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(isOwned ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                                        .foregroundColor(isOwned ? .blue : .orange)
                                        .cornerRadius(8)
                                    
                                    // Grace period indicator for owned rooms
                                    if isOwned && appData.isInGracePeriod, let gracePeriodEnd = appData.subscriptionGracePeriodEnd {
                                        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: gracePeriodEnd).day ?? 0
                                        
                                        Text("⚠️ \(daysRemaining)d left")
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.red.opacity(0.2))
                                            .foregroundColor(.red)
                                            .cornerRadius(8)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                            }
                            .background(cardBackgroundColor)
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 15) {
            Button(action: {
                if canCreateRoom {
                    showingCreateRoom = true
                } else {
                    if roomLimit <= 0 {
                        // No subscription - show subscription view
                        showingSubscriptionView = true
                    } else {
                        // Has subscription but reached limit
                        showingLimitReachedAlert = true
                    }
                }
            }) {
                HStack {
                    Image(systemName: "plus.circle")
                        .foregroundColor(canCreateRoom ? .white : .gray)
                    Text("Create New Room")
                        .font(.headline)
                        .foregroundColor(canCreateRoom ? .white : .gray)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canCreateRoom ? Color.blue : Color.gray.opacity(0.3))
                .cornerRadius(15)
            }
            .disabled(false) // Don't disable the button, handle the subscription check in the action
            .padding(.horizontal)
            
            Button(action: {
                showingJoinRoom = true
            }) {
                HStack {
                    Image(systemName: "person.badge.plus")
                        .foregroundColor(textColor)
                    Text("Join Room with Invite Code")
                        .font(.headline)
                        .foregroundColor(textColor)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(cardBackgroundColor)
                .cornerRadius(15)
            }
            .padding(.horizontal)
        }
    }
    
    private var availablePlansSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AVAILABLE PLANS")
                .font(.headline)
                .foregroundColor(subtitleColor)
                .padding(.leading)
            
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
                                isCurrentPlan: plan == subscriptionPlan,
                                currentRoomCount: ownedRoomCount,
                                isProcessing: storeManager.isLoading
                            ) {
                                selectedPackage = package
                                showingPurchaseConfirmation = true
                            }
                            .padding(.horizontal)
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
    
    private var footerSection: some View {
        HStack {
            Spacer()
            Button("Privacy Policy & User Agreement") {
                if let url = URL(string: "https://www.zthreesolutions.com/privacy-policy-user-agreement") {
                    UIApplication.shared.open(url)
                }
            }
            .foregroundColor(.blue)
            
            Spacer()
            

            Button("Terms of Service (EULA)") {
                if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                    UIApplication.shared.open(url)
                }
            }
            .foregroundColor(.blue)
            Spacer()
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Helper Methods
    
    private func loadCurrentRoomName() {
        guard let roomId = appData.currentRoomId else {
            currentRoomName = "No room selected"
            return
        }
        
        loadRoomName(roomId: roomId) { name in
            if let name = name {
                self.currentRoomName = name
            } else {
                self.currentRoomName = "Room \(roomId.prefix(6))"
            }
        }
    }
    
    private func loadRoomName(roomId: String, completion: @escaping (String?) -> Void) {
        let dbRef = Database.database().reference()
        dbRef.child("rooms").child(roomId).observeSingleEvent(of: .value) { snapshot, _ in
            if let roomData = snapshot.value as? [String: Any] {
                if let cycles = roomData["cycles"] as? [String: [String: Any]] {
                    var latestCycle: [String: Any]? = nil
                    var latestStartDate: Date? = nil
                    
                    for (_, cycleData) in cycles {
                        if let startDateStr = cycleData["startDate"] as? String,
                           let startDate = ISO8601DateFormatter().date(from: startDateStr) {
                            if latestStartDate == nil || startDate > latestStartDate! {
                                latestStartDate = startDate
                                latestCycle = cycleData
                            }
                        }
                    }
                    
                    if let latestCycle = latestCycle,
                       let patientName = latestCycle["patientName"] as? String,
                       !patientName.isEmpty && patientName != "Unnamed" {
                        completion("\(patientName)'s Program")
                        return
                    }
                    
                    for (_, cycleData) in cycles {
                        if let patientName = cycleData["patientName"] as? String,
                           !patientName.isEmpty && patientName != "Unnamed" {
                            completion("\(patientName)'s Program")
                            return
                        }
                    }
                }
                
                if let roomName = roomData["name"] as? String {
                    completion(roomName)
                    return
                }
            }
            completion("Unknown Program")
        }
    }
    
    private func refreshUserDataFromAppleAuth() {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        
        // Get Apple ID from provider data
        var appleId: String?
        for provider in firebaseUser.providerData {
            if provider.providerID == "apple.com" {
                appleId = provider.uid
                break
            }
        }
        
        guard let appleUserId = appleId else {
            print("No Apple ID found for user refresh")
            return
        }
        
        // ENCODE the Apple ID for Firebase safety
        let encodedAppleId = encodeForFirebase(appleUserId)
        print("Refreshing user data for encoded Apple ID: \(encodedAppleId)")
        
        let dbRef = Database.database().reference()
        dbRef.child("auth_mapping").child(encodedAppleId).observeSingleEvent(of: .value) { snapshot in
            guard let userIdString = snapshot.value as? String else {
                print("No mapping found for Apple ID: \(encodedAppleId)")
                return
            }
            
            dbRef.child("users").child(userIdString).observeSingleEvent(of: .value) { userSnapshot in
                if let userData = userSnapshot.value as? [String: Any] {
                    var userDict = userData
                    userDict["id"] = userIdString
                    
                    if let user = User(dictionary: userDict) {
                        DispatchQueue.main.async {
                            self.appData.currentUser = user
                            self.loadAvailableRooms()
                            self.loadUserSubscriptionStatus()
                        }
                    }
                }
            }
        }
    }

    // Add this helper method at the bottom of ManageRoomsAndSubscriptionsView
    private func encodeForFirebase(_ string: String) -> String {
        return string
            .replacingOccurrences(of: ".", with: "_DOT_")
            .replacingOccurrences(of: "#", with: "_HASH_")
            .replacingOccurrences(of: "$", with: "_DOLLAR_")
            .replacingOccurrences(of: "[", with: "_LBRACKET_")
            .replacingOccurrences(of: "]", with: "_RBRACKET_")
    }
    
    private func loadAvailableRooms() {
        guard let user = appData.currentUser else {
            errorMessage = "User not found"
            isLoading = false
            return
        }
        
        let userId = user.id.uuidString
        isLoading = true
        
        let dbRef = Database.database().reference()
        var rooms: [String: (String, Bool)] = [:]
        var userOwnedRooms = user.ownedRooms ?? []
        let dispatchGroup = DispatchGroup()
        
        // First load room access information
        dispatchGroup.enter()
        dbRef.child("users").child(userId).child("roomAccess").observeSingleEvent(of: .value) { snapshot, _ in
            if let roomAccess = snapshot.value as? [String: Any] {
                for (roomId, _) in roomAccess {
                    dispatchGroup.enter()
                    self.loadRoomName(roomId: roomId) { roomName in
                        let isOwned = userOwnedRooms.contains(roomId)
                        rooms[roomId] = (roomName ?? "Room \(roomId.prefix(6))", isOwned)
                        dispatchGroup.leave()
                    }
                }
            }
            dispatchGroup.leave()
        }
        
        // Also check rooms that have the user in their users list
        dispatchGroup.enter()
        dbRef.child("rooms").observeSingleEvent(of: .value) { snapshot, _ in
            if let allRooms = snapshot.value as? [String: [String: Any]] {
                for (roomId, roomData) in allRooms {
                    if let roomUsers = roomData["users"] as? [String: [String: Any]],
                       roomUsers[userId] != nil {
                        dispatchGroup.enter()
                        self.loadRoomName(roomId: roomId) { roomName in
                            let isOwned = userOwnedRooms.contains(roomId)
                            rooms[roomId] = (roomName ?? "Room \(roomId.prefix(6))", isOwned)
                            dispatchGroup.leave()
                        }
                    }
                }
            }
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) {
            self.availableRooms = rooms
            self.isLoading = false
        }
    }
    
    func loadUserSubscriptionStatus() {
        let dbRef = Database.database().reference()
        
        guard let user = appData.currentUser else {
            return
        }
        
        let userId = user.id.uuidString
        
        dbRef.child("users").child(userId).observeSingleEvent(of: .value) { snapshot in
            if let userData = snapshot.value as? [String: Any] {
                var updatedUser = user
                updatedUser.subscriptionPlan = userData["subscriptionPlan"] as? String
                updatedUser.roomLimit = userData["roomLimit"] as? Int ?? 0
                updatedUser.ownedRooms = userData["ownedRooms"] as? [String]
                
                DispatchQueue.main.async {
                    self.appData.currentUser = updatedUser
                    self.loadAvailableRooms()
                }
            }
        }
    }
    
    private func switchToRoom(roomId: String) {
        isSwitching = true
        
        appData.switchToRoom(roomId: roomId)
        
        // Allow some time for the switch to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isSwitching = false
            loadCurrentRoomName()
            loadAvailableRooms()
            
            // If in settings, dismiss this view and navigate to home
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: Notification.Name("NavigateToHomeTab"), object: nil)
                self.dismiss()
            }
        }
    }
    
    private func leaveRoom(roomId: String) {
        appData.leaveRoom(roomId: roomId) { success, error in
            if success {
                loadAvailableRooms()
                loadUserSubscriptionStatus()
            } else if let error = error {
                errorMessage = error
                showError = true
            }
        }
    }
    
    private func deleteRoom(roomId: String) {
        guard let ownedRooms = appData.currentUser?.ownedRooms,
              ownedRooms.contains(roomId) else {
            errorMessage = "You can only delete rooms you have created"
            showError = true
            return
        }
        
        appData.deleteRoom(roomId: roomId) { success, error in
            if success {
                loadAvailableRooms()
                loadUserSubscriptionStatus()
            } else if let error = error {
                errorMessage = error
                showError = true
            }
        }
    }
    
    private func purchasePackage(_ package: Package) {
        storeManager.purchasePackage(package, appData: appData) { success, error in
            if success {
                // UI will be updated via notification, no need for additional delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Just a small delay to ensure notification propagates
                }
            } else if let error = error {
                errorMessage = error
                showError = true
            }
        }
    }
}
