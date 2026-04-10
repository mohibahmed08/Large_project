import ActivityKit
import Flutter
import UIKit
import UserNotifications
import WidgetKit

private let kPushDebugChannel = "calendarplusplus/push_debug"
private let kLiveActivityChannel = "com.calendarpp/live_activity"
private let kWidgetDataChannel = "com.calendarpp/widget_data"
private let kSharedWidgetSuite = "group.com.jonathan.calendar.shared"
private let kSharedUpcomingTasksKey = "upcomingTasks"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    DispatchQueue.main.async {
      application.registerForRemoteNotifications()
    }
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let registrar = engineBridge.applicationRegistrar
    let messenger = registrar.messenger()
    setupPushDebugChannel(binaryMessenger: messenger)
    setupLiveActivityChannel(binaryMessenger: messenger)
    setupWidgetDataChannel(binaryMessenger: messenger)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }

  private func setupPushDebugChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: kPushDebugChannel,
      binaryMessenger: binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "APP_DELEGATE_DEALLOCATED",
            message: "AppDelegate no longer available",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "getNativeStatus":
        self.getNativeStatus(result: result)
      case "registerForRemoteNotifications":
        self.handleRegisterForRemoteNotifications(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setupLiveActivityChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: kLiveActivityChannel,
      binaryMessenger: binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "APP_DELEGATE_DEALLOCATED",
            message: "AppDelegate no longer available",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "startActivity":
        if #available(iOS 16.2, *) {
          self.handleStartActivity(call: call, result: result)
        } else {
          result(false)
        }
      case "updateActivity":
        if #available(iOS 16.2, *) {
          self.handleUpdateActivity(call: call, result: result)
        } else {
          result(nil)
        }
      case "endActivity":
        if #available(iOS 16.2, *) {
          self.handleEndActivity(call: call, result: result)
        } else {
          result(nil)
        }
      case "endAllActivities":
        if #available(iOS 16.2, *) {
          self.handleEndAllActivities(result: result)
        } else {
          result(nil)
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

  private func setupWidgetDataChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: kWidgetDataChannel,
      binaryMessenger: binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "updateWidgetData":
        self.handleUpdateWidgetData(call: call, result: result)
      case "clearWidgetData":
        self.handleClearWidgetData(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleRegisterForRemoteNotifications(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
      result([
        "requested": true,
        "isRegisteredForRemoteNotifications": UIApplication.shared.isRegisteredForRemoteNotifications,
      ])
    }
  }

  private func getNativeStatus(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let payload: [String: Any] = [
        "authorizationStatus": self.authorizationStatusString(settings.authorizationStatus),
        "alertSetting": self.notificationSettingString(settings.alertSetting),
        "badgeSetting": self.notificationSettingString(settings.badgeSetting),
        "soundSetting": self.notificationSettingString(settings.soundSetting),
        "lockScreenSetting": self.notificationSettingString(settings.lockScreenSetting),
        "notificationCenterSetting": self.notificationSettingString(settings.notificationCenterSetting),
        "carPlaySetting": self.notificationSettingString(settings.carPlaySetting),
        "alertStyle": self.alertStyleString(settings.alertStyle),
        "showPreviewsSetting": self.showPreviewsSettingString(settings.showPreviewsSetting),
        "isRegisteredForRemoteNotifications": UIApplication.shared.isRegisteredForRemoteNotifications,
        "backgroundRefreshStatus": self.backgroundRefreshStatusString(UIApplication.shared.backgroundRefreshStatus),
      ]
      result(payload)
    }
  }

  private func authorizationStatusString(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "notDetermined"
    case .denied:
      return "denied"
    case .authorized:
      return "authorized"
    case .provisional:
      return "provisional"
    case .ephemeral:
      return "ephemeral"
    @unknown default:
      return "unknown"
    }
  }

  private func notificationSettingString(_ setting: UNNotificationSetting) -> String {
    switch setting {
    case .notSupported:
      return "notSupported"
    case .disabled:
      return "disabled"
    case .enabled:
      return "enabled"
    @unknown default:
      return "unknown"
    }
  }

  private func alertStyleString(_ style: UNAlertStyle) -> String {
    switch style {
    case .none:
      return "none"
    case .banner:
      return "banner"
    case .alert:
      return "alert"
    @unknown default:
      return "unknown"
    }
  }

  private func showPreviewsSettingString(_ setting: UNShowPreviewsSetting) -> String {
    switch setting {
    case .always:
      return "always"
    case .whenAuthenticated:
      return "whenAuthenticated"
    case .never:
      return "never"
    @unknown default:
      return "unknown"
    }
  }

  private func backgroundRefreshStatusString(_ status: UIBackgroundRefreshStatus) -> String {
    switch status {
    case .available:
      return "available"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    @unknown default:
      return "unknown"
    }
  }

  @available(iOS 16.2, *)
  private func handleStartActivity(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: "Expected a map",
          details: nil
        )
      )
      return
    }

    guard
      let taskId = args["taskId"] as? String,
      let taskType = args["taskType"] as? String,
      let title = args["title"] as? String,
      let startMs = args["startTime"] as? Double
    else {
      result(
        FlutterError(
          code: "MISSING_ARGS",
          message: "taskId/taskType/title/startTime required",
          details: nil
        )
      )
      return
    }

    let endTime = (args["endTime"] as? Double).map {
      Date(timeIntervalSince1970: $0 / 1000)
    }
    let description = args["description"] as? String
    let location = args["location"] as? String
    let startTime = Date(timeIntervalSince1970: startMs / 1000)
    let attributes = CalendarLiveActivityAttributes(
      taskId: taskId,
      taskType: taskType
    )
    let state = CalendarLiveActivityAttributes.CalendarTaskState(
      title: title,
      startTime: startTime,
      endTime: endTime,
      description: description,
      location: location
    )

    do {
      let activity = try Activity<CalendarLiveActivityAttributes>.request(
        attributes: attributes,
        contentState: state,
        pushType: nil
      )
      result(activity.id)
    } catch {
      result(
        FlutterError(
          code: "START_FAILED",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  @available(iOS 16.2, *)
  private func handleUpdateActivity(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let activityId = args["activityId"] as? String,
          let title = args["title"] as? String,
          let startMs = args["startTime"] as? Double
    else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: "activityId/title/startTime required",
          details: nil
        )
      )
      return
    }

    let endTime = (args["endTime"] as? Double).map {
      Date(timeIntervalSince1970: $0 / 1000)
    }
    let description = args["description"] as? String
    let location = args["location"] as? String
    let isCompleted = args["isCompleted"] as? Bool ?? false
    let startTime = Date(timeIntervalSince1970: startMs / 1000)

    Task {
      for activity in Activity<CalendarLiveActivityAttributes>.activities
      where activity.id == activityId {
        let newState = CalendarLiveActivityAttributes.CalendarTaskState(
          title: title,
          startTime: startTime,
          endTime: endTime,
          description: description,
          location: location,
          isCompleted: isCompleted
        )
        await activity.update(using: newState)
      }
      result(nil)
    }
  }

  @available(iOS 16.2, *)
  private func handleEndActivity(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let activityId = args["activityId"] as? String
    else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: "activityId required",
          details: nil
        )
      )
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

  private func handleUpdateWidgetData(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let tasks = args["tasks"] as? [[String: Any]]
    else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: "tasks array required",
          details: nil
        )
      )
      return
    }

    let sanitizedTasks = tasks.map { sanitizePropertyListDictionary($0) }
    let defaults = UserDefaults(suiteName: kSharedWidgetSuite)
    defaults?.set(sanitizedTasks, forKey: kSharedUpcomingTasksKey)
    WidgetCenter.shared.reloadAllTimelines()
    result(nil)
  }

  private func handleClearWidgetData(result: @escaping FlutterResult) {
    let defaults = UserDefaults(suiteName: kSharedWidgetSuite)
    defaults?.removeObject(forKey: kSharedUpcomingTasksKey)
    WidgetCenter.shared.reloadAllTimelines()
    result(nil)
  }

  private func sanitizePropertyListDictionary(_ value: [String: Any]) -> [String: Any] {
    var sanitized: [String: Any] = [:]

    for (key, candidate) in value {
      if let safeValue = sanitizePropertyListValue(candidate) {
        sanitized[key] = safeValue
      }
    }

    return sanitized
  }

  private func sanitizePropertyListValue(_ value: Any) -> Any? {
    switch value {
    case is NSNull:
      return nil
    case let string as String:
      return string
    case let number as NSNumber:
      return number
    case let date as Date:
      return date
    case let data as Data:
      return data
    case let dictionary as [String: Any]:
      return sanitizePropertyListDictionary(dictionary)
    case let array as [Any]:
      return array.compactMap { sanitizePropertyListValue($0) }
    default:
      return nil
    }
  }
}

@available(iOS 16.2, *)
private struct CalendarLiveActivityAttributes: ActivityAttributes {
  public typealias ContentState = CalendarTaskState

  let taskId: String
  let taskType: String

  struct CalendarTaskState: Codable, Hashable {
    var title: String
    var startTime: Date
    var endTime: Date?
    var description: String?
    var location: String?
    var isCompleted: Bool

    init(
      title: String,
      startTime: Date,
      endTime: Date? = nil,
      description: String? = nil,
      location: String? = nil,
      isCompleted: Bool = false
    ) {
      self.title = title
      self.startTime = startTime
      self.endTime = endTime
      self.description = description
      self.location = location
      self.isCompleted = isCompleted
    }
  }
}
