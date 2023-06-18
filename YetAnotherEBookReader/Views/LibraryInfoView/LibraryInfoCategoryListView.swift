//
//  LibraryInfoCategoryListView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/29.
//

import SwiftUI
import RealmSwift

struct LibraryInfoCategoryListView: View {
    @EnvironmentObject var modelData: ModelData
    
    @EnvironmentObject var viewModel: LibraryInfoView.ViewModel

    @ObservedResults(CalibreUnifiedSearchObject.self) var unifiedSearches
    
    @ObservedResults(CalibreUnifiedCategoryObject.self, sortDescriptor: .init(keyPath: "categoryName")) var unifiedCategories
    
    @ObservedResults(CalibreUnifiedCategoryObject.self, where: { $0.search == "" }, sortDescriptor: .init(keyPath: "categoryName")) var unifiedCategoriesKeys
    
    var body: some View {
        Section {
            ForEach(unifiedCategoriesKeys) { unifiedCategoryKey in
                NavigationLink(tag: unifiedCategoryKey.categoryName, selection: $viewModel.categoriesSelected) {
//                NavigationLink {
                    ZStack {
                        TextField("Filter \(unifiedCategoryKey.categoryName)", text: $viewModel.categoryFilterString, onCommit: {
                            updateViewModel()
                        })
                        .keyboardType(.webSearch)
                        .padding([.leading, .trailing], 24)
                        .onChange(of: viewModel.categoryFilterString) { newValue in
                            viewModel.categoryFilter = viewModel.categoryFilterString.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        HStack {
                            Spacer()
                            Button {
                                viewModel.categoryFilterString = ""
                                updateViewModel()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .disabled(viewModel.categoryFilterString.isEmpty)
                            
                        }.padding([.leading, .trailing], 4)
                    }
                    
                    Divider()
                    
                    ZStack {
                        if let unifiedCategory = viewModel.unifiedCategoryObject {
                            LibraryInfoCategoryItemsView(unifiedCategory: unifiedCategory)
                                .environmentObject(viewModel)
                        } else {
                            Text("Missing List")
                        }
                    }
                    .navigationTitle("Category: \(unifiedCategoryKey.categoryName)")
                    .onAppear {
                        guard let categoryName = viewModel.categoriesSelected,
                              categoryName != viewModel.categoryName
                        else { return }
                        
                        viewModel.categoryFilterString = ""
                        updateViewModel()
                    }
                    .onDisappear {
                        if viewModel.categoriesSelected == nil {
                            viewModel.categoryName = ""
                        }
                    }
                } label: {
                    #if DEBUG
                    HStack {
                        Text("\(unifiedCategoryKey.categoryName)")
                        Spacer()
                        Text("\(unifiedCategoryKey.itemsCount) (\(unifiedCategoryKey.items.count)) (\(unifiedCategoryKey.totalNumber))")
                        
                    }
                    #else
                    Text("\(unifiedCategoryKey.categoryName)")
                    #endif
                }
                .isDetailLink(false)
            }
        } header: {
            Text("Browse by Category")
        }
    }
    
    func updateViewModel() {
        guard let categoryName = viewModel.categoriesSelected,
              categoryName.isEmpty == false
        else {
            return
        }
        
        viewModel.categoryName = categoryName
        
        let object = modelData.librarySearchManager.retrieveUnifiedCategoryObject(viewModel.categoryName, viewModel.categoryFilter, unifiedCategories)
        
        if object.realm == nil {
            $unifiedCategories.append(object)
        }
        
        viewModel.setUnifiedCategoryObject(modelData, object)
    }
}

//struct LibraryInfoCategoryListView_Previews: PreviewProvider {
//    static var previews: some View {
//        LibraryInfoCategoryListView()
//    }
//}
