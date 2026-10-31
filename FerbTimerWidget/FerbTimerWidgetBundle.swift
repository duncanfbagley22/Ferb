//
//  FerbTimerWidgetBundle.swift
//  FerbTimerWidget
//
//  Created by Duncan Bagley on 10/31/26.
//

import WidgetKit
import SwiftUI

@main
struct FerbTimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        FerbTimerWidget()
        FerbTimerWidgetLiveActivity()
    }
}
