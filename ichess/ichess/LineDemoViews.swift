//
//  LineDemoViews.swift
//  ichess
//
//  走法演示的说明文字（教练区和复盘共用）：当前这步醒目，上一步变淡，走到头再加一句总结。
//

import SwiftUI

struct DemoCaptionsView: View {
    let demo: LineDemo
    var showsPrevious = true
    let palette: BoardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if demo.index == 0 {
                Text(DemoCaption.intro(demo))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(4)
                    .minimumScaleFactor(0.9)
            } else {
                Text(DemoCaption.ply(demo, at: demo.index))
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                if demo.isAtEnd {
                    Text(DemoCaption.summary(demo))
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.demo)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                if showsPrevious, demo.index > 1 {
                    Text(DemoCaption.ply(demo, at: demo.index - 1))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
