# SyncMyFit

A Swift-based iOS app that syncs Google Health data to Apple Health, ensuring reliable tracking and full control over your health data.

## About the App

**SyncMyFit** is a personal project developed to bridge the gap between Google Health (Fitbit/Pixel Watch) data and Apple Health. It syncs data like steps, heart rate, sleep, and calories from the Google Health API into Apple Health using a custom app identifier to track origin. While it's currently designed for personal use, future plans include advanced features like:

- Auto Sync.
- Scheduled Notifications.
- Historical Data Sync.
- Enhanced Privacy & Pro Access Features.

## UI and Design

- Custom-built **light** and **dark mode** compatibility.
- Dedicated **light/dark app icons**.
- Smooth transitions and state management for login/logout.
- Alert-driven confirmations before logout.
- Circular progress visualizations for each health metric.

## Features

- Log in via Google OAuth 2.0.
- Securely store tokens using Keychain.
- Display last synced date and status.
- Show animated dashboard with visual metrics.
- View user account details with profile and logout option.

## Tech Stack

- **SwiftUI**: Declarative UI framework.
- **Combine**: Reactive framework for sync status and app state.
- **HealthKit**: To write data into Apple Health.
- **Google Health API**: For fetching fitness data.
- **Google People API**: For user profile display name.
- **Keychain**: Secure credential storage.
- **UserDefaults**: Persistent storage for sync timestamps.

## Setup Instructions

If you'd like to run **SyncMyFit** with your own Google Cloud credentials:

### Prerequisites

1. Create a [Google Cloud project](https://console.cloud.google.com/).
2. Enable the **Google Health API** in the API Library.
3. Create an **OAuth 2.0 Client ID** (type: Web Server).
4. Set the redirect URI to your reversed bundle ID (e.g., `com.googleusercontent.apps.{your-client-id}`).
5. Add your email as a test user in the [Audience](https://console.developers.google.com/auth/audience) page.
6. Add the scope `https://www.googleapis.com/auth/googlehealth.activity_and_fitness` and `https://www.googleapis.com/auth/userinfo.profile` in the [Data Access](https://console.developers.google.com/auth/scopes) page.

### Steps

1. Clone the repository:
    ```bash
    git clone https://github.com/your-username/SyncMyFit.git
    ```

2. Create a file called `Secrets.plist` at `SyncMyFit/Secrets.plist` with the following content:
    ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>GoogleClientID</key>
        <string>YOUR_CLIENT_ID.apps.googleusercontent.com</string>
        <key>GoogleClientSecret</key>
        <string>YOUR_CLIENT_SECRET</string>
    </dict>
    </plist>
    ```

3. Open the project in Xcode and ensure:
    - `Secrets.plist` is added to your **main target membership**.
    - `Secrets.swift` (already present) is used to load this securely.

4. Run the project on your iPhone (HealthKit requires a physical device).

## App Demo

[![Watch the demo](https://img.youtube.com/vi/9JEEu1LknRA/hqdefault.jpg)](https://youtube.com/shorts/9JEEu1LknRA)

## Current Version

**2.0.0** — Migrated to Google Health API.

## Disclaimer

This app is developed for personal use and is not affiliated with Google, Fitbit, or Apple.

## Developed By

Baranidharan Pasupathi
