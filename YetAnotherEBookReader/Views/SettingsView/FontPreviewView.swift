//
//  FontPreviewView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/12.
//

import SwiftUI

struct FontPreviewView: View {
    @State var fontId: String
    @State var fontInfo: FontInfo
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(fontId)
                Text(fontInfo.displayName ?? "")
                Text(fontInfo.localizedName ?? "")
                Text(fontInfo.fileURL?.lastPathComponent ?? "")
                Group {
                    Text("The quick brown fox jumps over the lazy dog and runs away.")
                    Divider()
                    
                    if fontInfo.languages.contains("en") {
                        Text("""
                            ABCDEFGHIJKLM
                            NOPQRSTUVWXYZ
                            abcdefghijklm
                            nopqrstuvwxyz
                            1234567890
                            """)
                        Divider()
                    }
                    if fontInfo.languages.contains("zh") {
                        Text(
                            """
                            汉体书写信息技术标准相容
                            档案下载使用界面简单
                            支援服务升级资讯专业制作
                            创意空间快速无线上网
                            ㈠㈡㈢㈣㈤㈥㈦㈧㈨㈩
                            AaBbCc ＡａＢｂＣｃ
                            """
                        )
                        Divider()
                    }
                    if fontInfo.languages.contains("ja") {
                        Text("""
                            あのイーハトーヴォの
                            すきとおった風、
                            夏でも底に冷たさをもつ青いそら、
                            うつくしい森で飾られたモリーオ市、
                            郊外のぎらぎらひかる草の波。
                            祇辻飴葛蛸鯖鰯噌庖箸
                            ABCDEFGHIJKLM
                            abcdefghijklm
                            1234567890
                            """)
                    }
                }.font(Font.custom(fontId, size: 25, relativeTo: .headline))
            }.padding()
        }
    }
}

struct FontPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        FontPreviewView(
            fontId: "PingFangSC",
            fontInfo: FontInfo(
                descriptor: CTFontDescriptorCreateWithNameAndSize("PingFangSC" as CFString, 30)
            )
        )
    }
}
