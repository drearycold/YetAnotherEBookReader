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
    
    var body: some View {
        Section {
            ForEach(unifiedCategories) { unifiedCategory in
                NavigationLink(tag: unifiedCategory.categoryName, selection: $viewModel.categoriesSelected) {
//                NavigationLink {
                    ZStack {
                        TextField("Filter \(unifiedCategory.categoryName)", text: $viewModel.categoryFilterString, onCommit: {
//                            modelData.categoryItemListSubject.send(unifiedCategory.categoryName)
                            
                        })
                        .keyboardType(.webSearch)
                        .padding([.leading, .trailing], 24)
                        .onChange(of: viewModel.categoryFilterString) { newValue in
                            viewModel.categoryFilter = viewModel.categoryFilterString.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        HStack {
                            Spacer()
                            Button(action: {
                                viewModel.categoryFilterString = ""
//                                modelData.categoryItemListSubject.send(unifiedCategory.categoryName)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }.disabled(viewModel.categoryFilterString.isEmpty)
                        }.padding([.leading, .trailing], 4)
                    }
                    
                    Divider()
                    
                    ZStack {
                        LibraryInfoCategoryItemsView(unifiedCategory: unifiedCategory)
                            .environmentObject(viewModel)
                    }
                    .navigationTitle("Category: \(unifiedCategory.categoryName)")
                    .onAppear {
                        guard let categoryName = viewModel.categoriesSelected,
                              categoryName != viewModel.categoryName
                        else { return }
                        
                        viewModel.categoryFilterString = ""
//                        modelData.categoryItemListSubject.send(categoryName)
                    }
                    .onDisappear {
                        if viewModel.categoriesSelected == nil {
                            viewModel.categoryName = ""
                        }
                    }
                } label: {
                    #if DEBUG
                    HStack {
                        Text("\(unifiedCategory.categoryName)")
                        Spacer()
                        Text("\(unifiedCategory.items.count) (\(unifiedCategory.totalNumber))")
                        
                    }
                    #else
                    Text("\(unifiedCategory.categoryName)")
                    #endif
                }
                .isDetailLink(false)
            }
        } header: {
            Text("Browse by Category")
        }
    }
}

//struct LibraryInfoCategoryListView_Previews: PreviewProvider {
//    static var previews: some View {
//        LibraryInfoCategoryListView()
//    }
//}
