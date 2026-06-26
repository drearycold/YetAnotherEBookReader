//
//  ActivityList.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/1.
//

import SwiftUI

struct ActivityList: View {
    @ObservedObject var viewModel: ActivityListViewModel

    @Binding var presenting: Bool

    init(viewModel: ActivityListViewModel, presenting: Binding<Bool>) {
        self.viewModel = viewModel
        self._presenting = presenting
    }

    init(viewModel: ActivityListViewModel, presenting: Bool? = nil) {
        self.viewModel = viewModel
        self._presenting = Binding<Bool>(get: { presenting ?? false }, set: { _ in })
    }

    var body: some View {
        List {
            ForEach(viewModel.activities, id: \.self) { obj in
                NavigationLink(destination: ActivityDetailView(obj: obj), label: {
                    row(obj: obj)
                })
            }
        }
        .navigationTitle("Recent Activities")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction, content: {
                if presenting {
                    Button(action: {
                        presenting = false
                    }) {
                        Image(systemName: "xmark")
                    }
                } else {
                    EmptyView()
                }
            })
        }
    }
    
    @ViewBuilder
    private func row(obj: ActivityLogUIEntry) -> some View {
        VStack {
            HStack {
                Text(obj.bookTitle.isEmpty ? obj.libraryName : obj.bookTitle)
                Spacer()
            }
            HStack {
                Text(obj.type)
                Spacer()
                Text(obj.errMsg)
            }.font(.caption)
            HStack {
                Text(obj.startDateString)
                Spacer()
                Text("->")
                Spacer()
                Text(obj.finishDateString)
            }.font(.caption)
        }
    }
}

struct ActivityDetailView: View {
    var obj: ActivityLogUIEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !obj.bookTitle.isEmpty {
                    Text("Book Title:").frame(minWidth: 100, alignment: .leading)
                    Text(obj.bookTitle)
                } else {
                    Text("Library Name:").frame(minWidth: 100, alignment: .leading)
                    Text(obj.libraryName)
                }
                Spacer()
            }.font(.title2)
            HStack {
                Text("Task:").frame(minWidth: 100, alignment: .leading)
                Text(obj.type).navigationTitle(obj.type)
                Spacer()
            }.font(.title3)
            HStack {
                Text("Start time:").frame(minWidth: 100, alignment: .leading)
                Text(obj.startDateLongString)
            }
            
            HStack {
                Text("Finish time:").frame(minWidth: 100, alignment: .leading)
                Text(obj.finishDateLongString)
            }
            
            HStack {
                Text("Result:").frame(minWidth: 100, alignment: .leading)
                Text(obj.errMsg)
            }
            
            Divider().padding(EdgeInsets(top: 16, leading: 0, bottom: 8, trailing: 0))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("More Infos")
                HStack {
                    Text("URL:").frame(minWidth: 64, alignment: .leading)
                    Text(obj.endpointURL)
                }
                HStack {
                    Text("Method:").frame(minWidth: 64, alignment: .leading)
                    Text(obj.httpMethod)
                }
                HStack(alignment: .top) {
                    Text("Body:").frame(minWidth: 64, alignment: .leading)
                    if let httpBodyString = obj.httpBodyString {
                        Text(httpBodyString)
                    } else {
                        Text("(Empty Body)")
                    }
                }
            }.font(.caption)
            
            Spacer()
        }
        .padding()
    }
}

struct ActivityList_Previews: PreviewProvider {
    static private var container = AppContainer(mock: true)
    
    @State static private var presenting = false
    static var previews: some View {
        NavigationView {
            ActivityList(
                viewModel: ActivityListViewModel(container: container),
                presenting: $presenting
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
