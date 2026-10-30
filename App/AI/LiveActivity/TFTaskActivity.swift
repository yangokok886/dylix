import ActivityKit
import Foundation

@available(iOS 16.2, *)
public struct TFTaskAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var stage: String
        public var count: Int
        public var steps: Int
        public var finished: Bool
    }
    public var startedAt: Date
}

@available(iOS 16.2, *)
@objc(TFTaskLiveActivity)
public final class TFTaskLiveActivity: NSObject {
    private static var current: Activity<TFTaskAttributes>?
    private static var desired: TFTaskAttributes.ContentState?
    private static var generation: Int = 0
    @objc public private(set) static var status: String = "尚未启动实时活动"
    @objc public static func update(_ stage: String, count: Int, steps: Int) {
        let state = TFTaskAttributes.ContentState(stage: String(stage.prefix(56)), count: count, steps: steps, finished: false)
        desired = state
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { status = "系统实时活动权限未开启"; return }
        if current == nil {
            // Reconcile stale activities after a previous process ended.
            let old = Activity<TFTaskAttributes>.activities
            Task { for activity in old { await activity.end(nil, dismissalPolicy: .immediate) } }
            do { current = try Activity.request(attributes: TFTaskAttributes(startedAt: Date()), content: ActivityContent(state: state, staleDate: nil), pushType: nil); status = "实时活动已启动" }
            catch { status = "实时活动启动失败：" + error.localizedDescription; NSLog("[AI Live Activity] %@", error.localizedDescription) }
        } else if let activity = current {
            generation += 1
            let revision = generation
            Task { @MainActor in
                guard revision == generation, let latest = desired else { return }
                await activity.update(ActivityContent(state: latest, staleDate: nil))
            }
        }
    }
    @objc public static func finish(_ success: Bool) {
        desired = nil
        generation += 1
        guard let activity = current else { return }
        current = nil
        let state = TFTaskAttributes.ContentState(stage: success ? "处理完成" : "请查看会话", count: 0, steps: 0, finished: true)
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(8))) }
    }
}
