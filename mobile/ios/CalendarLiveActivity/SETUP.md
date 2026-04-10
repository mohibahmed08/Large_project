# Live Activities Setup

The repo-side pieces are now in place:

- Flutter already starts, updates, and ends one Live Activity candidate via `lib/services/live_activity_service.dart`
- the active iOS app target now exposes the `com.calendarpp/live_activity` method channel in `ios/Runner/AppDelegate.swift`
- widget extension source files now live in `ios/CalendarLiveActivity/`

What still must be done in Xcode:

1. Create a new `Widget Extension` target named `CalendarLiveActivity`
2. Set that extension target's deployment target to iOS 16.2 or newer
3. Add these files to the extension target:
   - `ios/CalendarLiveActivity/CalendarLiveActivityAttributes.swift`
   - `ios/CalendarLiveActivity/CalendarLiveActivityWidget.swift`
4. Add an extension `Info.plist` with:
   - `NSSupportsLiveActivities = YES`
   - `NSSupportsLiveActivitiesFrequentUpdates = YES`
5. Ensure the host app keeps Push Notifications enabled and Background Modes includes `Remote notifications`

Notes:

- The host app can stay on an older deployment target because the `ActivityKit` calls are guarded with `@available(iOS 16.2, *)`
- The extension itself cannot; it must target iOS 16.2+
- If you want the Live Activity to open a specific task when tapped, that would be a small follow-up after the extension target is created
