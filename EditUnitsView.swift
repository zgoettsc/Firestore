import SwiftUI

struct EditUnitsView: View {
    @ObservedObject var appData: AppData
    @State private var showingAddUnit = false
    @State private var unitToDelete: Unit?
    @State private var showingDeleteConfirmation = false
    @State private var isEditing = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Form {
            Section(header:
                HStack {
                    Image(systemName: "ruler")
                        .foregroundColor(.purple)
                    Text("UNITS")
                        .foregroundColor(.purple)
                }
            ) {
                if appData.units.isEmpty {
                    Text("No units added")
                        .foregroundColor(.gray)
                        .italic()
                } else {
                    ForEach(appData.units.indices, id: \.self) { index in
                        HStack {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.purple)
                                .padding(.trailing, 4)
                            
                            unitRow(index: index)
                        }
                    }
                    .onDelete(perform: isEditing ? deleteUnit : nil)
                    .onMove(perform: isEditing ? moveUnits : nil)
                }
            }
            
            Section {
                Button(action: {
                    showingAddUnit = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                        Text("Add New Unit")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Edit Units")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    isEditing.toggle()
                }
            }
        }
        .environment(\.editMode, .constant(isEditing ? EditMode.active : EditMode.inactive))
        .sheet(isPresented: $showingAddUnit) {
            AddUnitView(appData: appData)
        }
        .alert("Delete \(unitToDelete?.name ?? "")?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { unitToDelete = nil }
            Button("Delete", role: .destructive) {
                if let unit = unitToDelete, let index = appData.units.firstIndex(where: { $0.id == unit.id }) {
                    appData.units.remove(at: index)
                }
                unitToDelete = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    // Extracted TextField into a separate function to simplify type checking
    private func unitRow(index: Int) -> some View {
        TextField("Unit (e.g., mg)", text: Binding(
            get: { appData.units[index].name },
            set: { newValue in
                if !newValue.isEmpty && !appData.units.contains(where: { $0.name == newValue && $0.id != appData.units[index].id }) {
                    appData.units[index] = Unit(id: appData.units[index].id, name: newValue)
                }
            }
        ))
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .submitLabel(.done)
        .padding(.vertical, 4)
    }
    
    func deleteUnit(at offsets: IndexSet) {
        appData.units.remove(atOffsets: offsets)
    }
    
    func moveUnits(from source: IndexSet, to destination: Int) {
        appData.units.move(fromOffsets: source, toOffset: destination)
    }
}

struct EditUnitsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            EditUnitsView(appData: AppData())
        }
    }
}
