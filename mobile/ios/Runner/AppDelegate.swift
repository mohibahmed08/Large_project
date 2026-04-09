import ActivityKit
import Flutter
import UIKit

// ─── Method channel name must match the Dart side ────────────────────────────
private let kLiveActivityChannel = "com.calendarpp/live_activity"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    setupLiveActivityChannel(binaryMessenger: engineBridge.binaryMessenger)
  }

  // ─── Live Activity method channel ────────────────────────────────────────
  private func setupLiveActivityChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: kLiveActivityChannel,
      binaryMessenger: binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {

      case "startActivity":
        if #available(iOS 16.2, *) {
          self?.handleStartActivity(call: call, result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }

      case "updateActivity":
        if #available(iOS 16.2, *) {
          self?.handleUpdateActivity(call: call, result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }

      case "endActivity":
        if #available(iOS 16.2, *) {
          self?.handleEndActivity(call: call, result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }

      case "endAllActivities":
        if #available(iOS 16.2, *) {
          self?.handleEndAllActivities(result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }

      case "isSupported":
        if #available(iOS 16.2, *) {
          result(ActivityAuthorizationInfo().areActivitiesEnabled)
        } else {
          result(false)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // ── Start a new Live Activity ─────────────────────────────────────────────
  @available(iOS 16.2, *)
  private func handleStartActivity(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGS", message: "Expected a map", details: nil))
      return
    }

    guard
      let taskId    = args["taskId"]    as? String,
      let taskType  = args["taskType"]  as? String,
      let title     = args["title"]     as? String,
      let startMs   = args["startTime"] as? Double
    else {
      result(FlutterError(code: "MISSING_ARGS", message: "taskId/taskType/title/startTime required", details: nil))
      return
    }

    let endTime  = (args["endTime"]  as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
    let location = args["location"] as? String
    let startTime = Date(timeIntervalSince1970: startMs / 1000)

    let attributes = CalendarLiveActivityAttributes(taskId: taskId, taskType: taskType)
    let state = CalendarLiveActivityAttributes.CalendarTaskState(
      title:     title,
      startTime: startTime,
      endTime:   endTime,
      location:  location
    )

    do {
      let activity = try Activity<CalendarLiveActivityAttributes>.request(
        attributes: attributes,
        contentState: state,
        pushType: nil   // set to .token to enable server push-to-update
      )
      result(activity.id)
    } catch {
      result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  // ── Update an existing Live Activity ─────────────────────────────────────
  @available(iOS 16.2, *)
  private func handleUpdateActivity(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let activityId = args["activityId"] as? String,
          let title      = args["title"]      as? String,
          let startMs    = args["startTime"]  as? Double
    else {
      result(FlutterError(code: "INVALID_ARGS", message: "activityId/title/startTime required", details: nil))
      return
    }

    let endTime   = (args["endTime"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
    let location  = args["location"] as? String
    let completed = args["isCompleted"] as? Bool ?? false
    let startTime = Date(timeIntervalSince1970: startMs / 1000)

    Task {
      for activity in Activity<CalendarLiveActivityAttributes>.activities
      where activity.id == activityId {
        let newState = CalendarLiveActivityAttributes.CalendarTaskState(
          title:       title,
          startTime:   startTime,
          endTime:     endTime,
          location:    location,
          isCompleted: completed
        )
        await activity.update(using: newState)
      }
      result(nil)
    }
  }

  // ── End / dismiss a Live Activity ─────────────────────────────────────────
  @available(iOS 16.2, *)
  private func handleEndActivity(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let activityId = args["activityId"] as? String
    else {
      result(FlutterError(code: "INVALID_ARGS", message: "activityId required", details: nil))
      return
    }

    Task {
      for activity in Activity<CalendarLiveActivityAttributes>.activities
      where activity.id == activityId {
        await activity.end(dismissalPolicy: .immediate)
      }
      result(nil)
    }
  }

  @available(iOS 16.2, *)
  private func handleEndAllActivities(result: @escaping FlutterResult) {
    Task {
      for activity in Activity<CalendarLiveActivityAttributes>.activities {
        await activity.end(dismissalPolicy: .immediate)
      }
      result(nil)
    }
  }
}
