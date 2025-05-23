//
//  PlanRowView.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 5/20/25.
//


import SwiftUI
import RevenueCat

struct PlanRowView: View {
    let plan: SubscriptionPlan
    let package: Package
    let isCurrentPlan: Bool
    let currentRoomCount: Int
    let isProcessing: Bool
    let onTap: () -> Void
    
    private var isDowngradeBlocked: Bool {
        return currentRoomCount > plan.roomLimit
    }
    
    private var statusText: String {
        if isCurrentPlan {
            return "Current"
        } else if isDowngradeBlocked {
            let roomsToDelete = currentRoomCount - plan.roomLimit
            return "Delete \(roomsToDelete) room\(roomsToDelete > 1 ? "s" : "") first"
        } else if currentRoomCount > plan.roomLimit {
            return "Downgrade"
        } else {
            return ""
        }
    }
    
    private var statusColor: Color {
        if isCurrentPlan {
            return .green
        } else if isDowngradeBlocked {
            return .red
        } else if currentRoomCount > plan.roomLimit {
            return .orange
        } else {
            return .blue
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(package.localizedPriceString + "/month")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(statusColor.opacity(0.1))
                        .cornerRadius(8)
                        .multilineTextAlignment(.center)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isCurrentPlan ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCurrentPlan ? Color.blue : (isDowngradeBlocked ? Color.red : Color.clear), lineWidth: 2)
            )
        }
        .disabled(isCurrentPlan || isProcessing || isDowngradeBlocked)
        .buttonStyle(PlainButtonStyle())
    }
}