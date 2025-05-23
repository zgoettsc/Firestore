//
//  NameInputView.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 5/20/25.
//


import SwiftUI

struct NameInputView: View {
    @Binding var isPresented: Bool
    let appleSignInResult: AppleSignInResult
    let onNameSubmitted: (String) -> Void
    
    @State private var name: String = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                VStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.blue)
                    
                    Text("Welcome!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Please enter your name to complete setup")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 16) {
                    TextField("Your Name", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.body)
                    
                    Button(action: {
                        submitName()
                    }) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Continue")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                    .cornerRadius(10)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            // Pre-fill with Apple provided name if available
            if let displayName = appleSignInResult.displayName, !displayName.isEmpty {
                name = displayName
            }
        }
    }
    
    private func submitName() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        isLoading = true
        onNameSubmitted(trimmedName)
    }
}