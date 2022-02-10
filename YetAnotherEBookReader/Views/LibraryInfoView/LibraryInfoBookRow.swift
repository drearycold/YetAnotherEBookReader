//
//  LibraryInfoBookRow.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/6/15.
//

import SwiftUI
import struct Kingfisher.KFImage

struct LibraryInfoBookRow: View {
    @EnvironmentObject var modelData: ModelData
    
    let bookId: Int32
    
    var body: some View {
        HStack {
            if let book = modelData.calibreServerLibraryBooks[bookId] {
                KFImage(book.coverURL)
                    .placeholder {
                        ProgressView().progressViewStyle(CircularProgressViewStyle())
                    }
                    .resizable()
                    .frame(width: 64, height: 96, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(book.title)").font(.headline)
                    
                    HStack {
                        Text("\(book.authorsDescriptionShort)").font(.subheadline)
                        Spacer()
                        Text(book.ratingDescription).font(.subheadline)
                    }
                    
                    HStack {
                        if book.inShelf {
                            Image(systemName: "books.vertical")
                        } else {
                            Image(systemName: "books.vertical")
                                .hidden()
                        }
                        if book.identifiers["goodreads"] != nil {
                            Image("icon-goodreads")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20, alignment: .center)
                        } else {
                            Image("icon-goodreads")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20, alignment: .center)
                                .hidden()
                        }
                        if book.identifiers["amazon"] != nil {
                            Image("icon-amazon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20, alignment: .center)
                        } else {
                            Image("icon-amazon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20, alignment: .center)
                                .hidden()
                        }
                        Spacer()
                        if book.formats["PDF"] != nil {
                            Image("PDF")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20, alignment: .center)
                        } else {
                            Image("PDF")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20, alignment: .center)
                                .hidden()
                        }
                        
                        if book.formats["EPUB"] != nil {
                            Image("EPUB")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20, alignment: .center)
                        } else {
                            Image("EPUB")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20, alignment: .center)
                                .hidden()
                        }
                    }
                }
            }
        }
    }
}

//struct LibraryInfoBookRow_Previews: PreviewProvider {
//    static var previews: some View {
//        LibraryInfoBookRow(bookId: 1)
//    }
//}
