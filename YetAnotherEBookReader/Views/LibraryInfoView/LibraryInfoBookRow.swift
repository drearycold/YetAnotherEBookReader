//
//  LibraryInfoBookRow.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/6/15.
//

import SwiftUI
import RealmSwift
import struct Kingfisher.KFImage

struct LibraryInfoBookRow: View {
    @EnvironmentObject var modelData: ModelData

    @EnvironmentObject var viewModel: LibraryInfoView.ViewModel

    @ObservedRealmObject var unifiedSearchObject: CalibreUnifiedSearchObject

    @ObservedRealmObject var bookRealm: CalibreBookRealm
    
    var body: some View {
        if let book = modelData.convert(bookRealm: bookRealm) {
            HStack {
                //                            if let index = unifiedSearchObject.getIndex(primaryKey: bookRealm.primaryKey!) {
                //                                Text(index.description)
                //                            }
                if let bookIndex = self.modelData.librarySearchManager.getMergedBookIndex(mergedKey: .init(libraryIds: viewModel.filterCriteriaLibraries, criteria: viewModel.currentLibrarySearchCriteria), primaryKey: bookRealm.primaryKey!){
                    Text(bookIndex.description)
                        .frame(minWidth: 40)
                        .onAppear {
                            guard bookIndex > unifiedSearchObject.limitNumber - 20
                            else {
                                return
                            }
                            
                            viewModel.expandSearchUnifiedBookLimit(unifiedSearchObject)
                        }
                }
//                                    bookRowView(book: book, bookRealm: bookRealm)
                HStack(alignment: .bottom) {
                    ZStack {
                        KFImage(book.coverURL)
                            .placeholder {
                                ProgressView().progressViewStyle(CircularProgressViewStyle())
                            }
                            .resizable()
                            .frame(width: 72, height: 96, alignment: .center)
                        
                        if book.inShelf {
                            Image(systemName: "books.vertical")
                                .frame(width: 64 - 8, height: 96 - 8, alignment: .bottomTrailing)
                                .foregroundColor(.primary)
                                .opacity(0.8)
                        }
                        
                        if let download = modelData.activeDownloads.filter( { $1.book.id == book.id && ($1.isDownloading || $1.resumeData != nil) } ).first?.value {
                            ZStack {
                                Rectangle()
                                    .frame(width: 64, height: 64, alignment: .center)
                                    .foregroundColor(.gray)
                                    .cornerRadius(4.0)
                                    .opacity(0.8)
                                ProgressView(value: download.progress)
                                    .frame(width: 56, height: 64, alignment: .center)
                                    .progressViewStyle(.linear)
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 64, height: 96 - 8, alignment: .bottom)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 2) {
        //                #if DEBUG
        //                HStack {
        //                    Text("Book")
        //                    Text("\(book.id)")
        //                    Spacer()
        //                    Text(book.inShelfId)
        //                }
        //                HStack {
        //                    Text("BookRealm")
        //                    Text("\(bookRealm.idInLib)")
        //                    Spacer()
        //                    Text(bookRealm.primaryKey!)
        //                }
        //                #endif

                        Text("\(book.title)")
                            .font(.callout)
                            .lineLimit(3)
                        
                        Group {
                            HStack {
                                Text("\(book.authorsDescriptionShort)")
                                Spacer()
                                Text(book.lastModifiedByLocale)
                            }
                            
                            HStack {
                                Text(book.tags.first ?? "")
                                Spacer()
                                Text(book.library.name)
                            }
                        }
                        .font(.caption)
                        .lineLimit(1)
                        
                        Spacer()
                        
                        HStack {
                            if book.identifiers["goodreads"] != nil {
                                Image("icon-goodreads")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 16, alignment: .center)
                            } else {
                                Image("icon-goodreads")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 16, alignment: .center)
                                    .hidden()
                            }
                            if book.identifiers["amazon"] != nil {
                                Image("icon-amazon")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 16, alignment: .center)
                            } else {
                                Image("icon-amazon")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 16, alignment: .center)
                                    .hidden()
                            }
                            Spacer()
                            
                            Text(book.ratingDescription).font(.caption)
                            
                            Spacer()
                            if book.formats["PDF"] != nil {
                                Image("PDF")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 16, alignment: .center)
                            } else {
                                Image("PDF")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 16, alignment: .center)
                                    .hidden()
                            }
                            
                            if book.formats["EPUB"] != nil {
                                Image("EPUB")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 16, alignment: .center)
                            } else {
                                Image("EPUB")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 16, alignment: .center)
                                    .hidden()
                            }
                            
                            if book.formats["CBZ"] != nil {
                                Image("CBZ")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 16, alignment: .center)
                            } else {
                                Image("CBZ")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 16, alignment: .center)
                                    .hidden()
                            }
                        }
                    }
                }
            }
        } else {
            Text(bookRealm.title)
        }
        
    }
}

//struct LibraryInfoBookRow_Previews: PreviewProvider {
//    static private var modelData = ModelData(mock: true)
//
//    static var previews: some View {
//        List{
//            LibraryInfoBookRow(book: Binding<CalibreBook>(get: {
//                modelData.booksInShelf.first!.value
//            }, set: { _ in
//
//            }))
//        }.environmentObject(modelData)
//    }
//}
