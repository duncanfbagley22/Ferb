//
//  FerbTimerWidgetLiveActivity.swift
//  FerbTimerWidget
//
//  Created by Duncan Bagley on 10/31/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct FerbTimerWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct FerbTimerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FerbTimerWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension FerbTimerWidgetAttributes {
    fileprivate static var preview: FerbTimerWidgetAttributes {
        FerbTimerWidgetAttributes(name: "World")
    }
}

extension FerbTimerWidgetAttributes.ContentState {
    fileprivate static var smiley: FerbTimerWidgetAttributes.ContentState {
        FerbTimerWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: FerbTimerWidgetAttributes.ContentState {
         FerbTimerWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: FerbTimerWidgetAttributes.preview) {
   FerbTimerWidgetLiveActivity()
} contentStates: {
    FerbTimerWidgetAttributes.ContentState.smiley
    FerbTimerWidgetAttributes.ContentState.starEyes
}
