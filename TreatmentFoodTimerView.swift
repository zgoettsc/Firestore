import SwiftUI

struct TreatmentFoodTimerView: View {
    @ObservedObject var appData: AppData
    @Environment(\.isInsideNavigationView) var isInsideNavigationView
    
    init(appData: AppData) {
        self.appData = appData
    }
    
    var body: some View {
        Form {
            Section(header:
                HStack {
                    Image(systemName: "timer")
                        .foregroundColor(.purple)
                    Text("TREATMENT FOOD TIMER")
                        .foregroundColor(.purple)
                }
            ) {
                Toggle("Enable Notification", isOn: Binding(
                    get: { appData.currentUser?.treatmentFoodTimerEnabled ?? false },
                    set: { newValue in
                        appData.setTreatmentFoodTimerEnabled(newValue)
                        if !newValue {
                            cancelAllTreatmentTimers()
                        }
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .purple))
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("When enabled, a notification will alert the user 15 minutes after a treatment food is logged. The Home tab will always display the remaining timer duration.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.vertical, 4)
                    
                    if appData.currentUser?.treatmentFoodTimerEnabled ?? false {
                        HStack(spacing: 20) {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.purple)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notification")
                                    .font(.headline)
                                Text("15 minute countdown")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .navigationTitle("Treatment Food Timer")
        .onAppear {
            if isInsideNavigationView {
                print("TreatmentFoodTimerView is correctly inside a NavigationView")
            } else {
                print("Warning: TreatmentFoodTimerView is not inside a NavigationView")
            }
        }
    }
    
    func cancelAllTreatmentTimers() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
