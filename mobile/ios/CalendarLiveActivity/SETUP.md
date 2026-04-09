# Live Activities and Firebase Setup Checklist

The Flutter, Swift, and backend code is in place. The remaining items below are the manual Apple/Firebase project steps that cannot be completed safely from inside the repo alone.

## 1. Add the Widget Extension target

1. In Xcode, **File -> New -> Target -> Widget Extension**
2. Name it exactly **CalendarLiveActivity**
3. **Uncheck** "Include Configuration App Intent" (not needed)
4. When prompted to activate the scheme, click **Activate**

## 2. Add the source files to the target

Drag both files from `ios/CalendarLiveActivity/` into the new target:
- `CalendarLiveActivityAttributes.swift`
- `CalendarLiveActivityWidget.swift`

Make sure **Target Membership** shows only `CalendarLiveActivity` (not Runner).

## 3. Enable Live Activities in the extension's Info.plist

In `CalendarLiveActivity/Info.plist` add:

```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>NSSupportsLiveActivitiesFrequentUpdates</key>
<true/>
```

Note:
`Runner/Info.plist` in the repo already includes the matching host-app Live Activities keys.

## 4. Enable the Push Notifications capability on the Runner target

Runner target -> Signing & Capabilities -> **+ Capability -> Push Notifications**

Recommended:
also enable **Background Modes -> Remote notifications** if you want to expand into richer background push handling later.

## 5. Add Firebase for FCM push

1. Download `GoogleService-Info.plist` from the Firebase console
2. Drag it into `ios/Runner/` with target membership set to Runner only
3. Make sure the Firebase iOS app bundle ID matches the Runner bundle ID
4. Upload your APNs auth key or certificates in Firebase Console -> Project Settings -> Cloud Messaging
5. Run `flutter pub get`
6. Run `cd ios && pod install`

## 6. Set the FCM server key on the backend

In your `.env` or hosting environment:

```env
FCM_SERVER_KEY=<your-firebase-server-key>
```

Get it from Firebase Console -> Project Settings -> Cloud Messaging -> **Server key**.

## 7. What the app already does

Once the Xcode/Firebase steps are complete, the current codebase will:

- initialise Firebase on app startup when native config is present
- request push permission after login
- upload the FCM device token to the backend
- remove the token on logout
- show foreground notifications as local alerts
- route reminder notification taps back into the app's calendar day view
- sync one Live Activity for the nearest ongoing item or the next upcoming item within the configured window
- update or end that Live Activity as calendar data changes
- render Lock Screen and Dynamic Island views via the widget extension source in this folder

## 8. Final validation checklist

- Login on a real iPhone and confirm the permission prompt appears
- Verify `/api/registerdevicetoken` receives the device token
- Create an item with a reminder and confirm both email and push are received
- Tap the push notification and confirm the app jumps to the correct day
- Confirm a nearby upcoming or ongoing item appears as a Live Activity
- Mark that item complete and confirm the Live Activity updates or disappears as expected
