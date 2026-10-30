import ActivityKit
import SwiftUI
import WidgetKit
import TFTaskActivity

@main
struct TFActivityWidgets: WidgetBundle {
    var body: some Widget { TFActivityWidget() }
}
struct TFActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TFTaskAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.finished ? "checkmark.circle" : "sparkles").font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dylix AI").font(.headline)
                    Text(context.state.stage).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !context.state.finished { ProgressView().controlSize(.small).frame(width: 20, height: 20) }
            }.padding(16).activityBackgroundTint(Color(.secondarySystemBackground))
             .widgetURL(URL(string: "tweakforge://ai"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("Dylix", systemImage: "sparkles").font(.subheadline).lineLimit(1).minimumScaleFactor(0.75) }
                DynamicIslandExpandedRegion(.trailing) { if !context.state.finished { ProgressView().controlSize(.small).frame(width: 20, height: 20) } }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.stage).font(.subheadline).lineLimit(2)
                        HStack {
                            Text(context.state.count > 1 ? "\(context.state.count) 个会话处理中" : "AI 会话")
                            Spacer()
                            Text("已处理 \(context.state.steps) 步")
                        }.font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(.white)
            } compactTrailing: {
                if context.state.finished { Image(systemName: "checkmark").font(.system(size: 11)) }
                else { ProgressView().controlSize(.mini).tint(.white).frame(width: 14, height: 14) }
            } minimal: {
                Image(systemName: context.state.finished ? "checkmark" : "sparkles").font(.system(size: 12))
            }.keylineTint(.white).widgetURL(URL(string: "tweakforge://ai"))
        }
    }
}
