# Migration Plan: Fitbit Web API → Google Health API

## Why Migrate

Fitbit Web API deprecated September 2026. Google Health API (`health.googleapis.com/v4`) replaces it. All Fitbit OAuth tokens will stop working after cutoff.

## Current State

Working v1.0.0 SwiftUI app:
```
Fitbit OAuth2 + PKCE → Fitbit REST API → HealthKit writes
```

11 Swift files, single-day (today only) sync, no cursor tracking.

## Target State

```
Google OAuth 2.0 → Google Health API → HealthKit writes
```

Same pipeline, different auth + data source. HealthKit writes unchanged.

---

## API Comparison

### Auth

| | Fitbit (current) | Google Health (target) |
|---|---|---|
| Provider | `fitbit.com` | `accounts.google.com` |
| Flow | OAuth2 + PKCE | OAuth2 + client_secret |
| Token endpoint | `api.fitbit.com/oauth2/token` | `oauth2.googleapis.com/token` |
| Scopes | `activity heartrate profile sleep` | `https://www.googleapis.com/auth/googlehealth.activity_and_fitness` |
| Client auth | Public (PKCE only) | Confidential (client_secret required) |

### Data Endpoints

| Data Type | Fitbit Endpoint | Google Health Endpoint |
|---|---|---|
| Steps | `/1/user/-/activities/date/{date}.json` | `/v4/users/me/dataTypes/steps/dataPoints?startTime=...&endTime=...` |
| Heart Rate | `/1/user/-/activities/heart/date/{date}/1d/1min.json` | `/v4/users/me/dataTypes/heart_rate/dataPoints?startTime=...&endTime=...` |
| Sleep | `/1.2/user/-/sleep/date/{date}.json` | `/v4/users/me/dataTypes/sleep_session/dataPoints?startTime=...&endTime=...` |
| Calories | `/1/user/-/activities/date/{date}.json` | `/v4/users/me/dataTypes/total_calories/dataPoints?startTime=...&endTime=...` |
| Profile | `/1/user/-/profile.json` | `/v4/users/me/profile` |

### Response Format

**Fitbit (current):** Nested per-endpoint JSON
```json
{
  "summary": { "steps": 8432 },
  "activities-heart-intraday": { "dataset": [{"value": 72}] }
}
```

**Google Health (target):** Unified dataPoints array
```json
{
  "dataPoints": [
    { "startTime": "2026-07-05T00:00:00Z", "endTime": "2026-07-05T23:59:59Z", "value": 8432 }
  ]
}
```

---

## Prerequisites

### 1. Google Cloud Setup

1. Create Google Cloud project (or use existing)
2. Enable **Google Health API** in API Library
3. Create OAuth 2.0 Client ID:
   - Type: **Web Server**
   - Redirect URI: `https://www.google.com` (Google's default)
4. Copy **Client ID** and **Client Secret**
5. Add test user email in Audience page

### 2. Secrets.plist Updates

Remove Fitbit keys, add Google keys:
```xml
<key>GoogleClientID</key>
<string>YOUR_GOOGLE_CLIENT_ID</string>
<key>GoogleClientSecret</key>
<string>YOUR_GOOGLE_CLIENT_SECRET</string>
```

### 3. Xcode Project Config

- Add URL scheme for Google OAuth callback (or keep `syncmyfit://`)
- Update `Info.plist` with `CFBundleURLTypes` if using Google Sign-In SDK
- Consider adding `GoogleSignIn` SPM package for native Google sign-in UI

---

## Implementation Steps

### Step 1: Create `GoogleHealthAuthManager.swift`

**New file.** Replace `FitbitAuthManager.swift`.

Responsibilities:
- Launch Google OAuth in `ASWebAuthenticationSession`
- Exchange auth code for tokens at `oauth2.googleapis.com/token`
- Refresh tokens at same endpoint
- Store tokens in Keychain via `KeychainHelper`
- Auto-refresh on 401
- Validate token expiry

Key differences from FitbitAuthManager:
- Requires `client_secret` in token exchange (Fitbit used PKCE only)
- Different auth URL structure (`accounts.google.com/o/oauth2/v2/auth`)
- Different scope format (full URL vs space-separated words)
- No PKCE needed (client_secret provides proof)

### Step 2: Create `HealthDataPoint.swift`

**New file.** Data model for Google Health API response.

```swift
struct HealthDataPoint: Codable {
    let startTime: String
    let endTime: String
    let value: Double
}

struct HealthDataResponse: Codable {
    let dataPoints: [HealthDataPoint]
}
```

### Step 3: Create `GoogleHealthClient.swift`

**New file.** Replace fetch methods in `SyncController.swift`.

Methods:
- `fetchSteps(since: Date, to: Date)` → `[HealthDataPoint]`
- `fetchHeartRate(since: Date, to: Date)` → `[HealthDataPoint]`
- `fetchSleep(since: Date, to: Date)` → `[HealthDataPoint]`
- `fetchCalories(since: Date, to: Date)` → `[HealthDataPoint]`
- `fetchProfile()` → `String` (display name)

All use `GoogleHealthAuthManager.shared.performAuthenticatedRequest()`.

### Step 4: Update `SyncController.swift`

Replace Fitbit API calls with `GoogleHealthClient` calls. Keep orchestration logic. Update parsing to use `HealthDataPoint` models.

### Step 5: Update `AppState.swift`

Replace all `FitbitAuthManager.shared` references with `GoogleHealthAuthManager.shared`.

### Step 6: Update Views

| File | Change |
|---|---|
| `LoginView.swift` | Button text: "Sign in with Google". Call `GoogleHealthAuthManager` |
| `DashboardView.swift` | Use `GoogleHealthClient` in `loadData()` |
| `AccountView.swift` | Logout calls `GoogleHealthAuthManager.shared.logout()` |
| `SyncMyFitApp.swift` | Replace `.onOpenURL` handler with Google OAuth callback |

### Step 7: Update `HealthKitManager.swift`

Minimal change: update `metadata["SyncSource"]` from `"Fitbit"` to `"Google Health"` (or `"SyncMyFit"`). Update delete filter in `deleteExistingSamples()` to match new metadata value.

---

## Files Summary

### Create (3)

| File | Purpose |
|---|---|
| `Services/GoogleHealthAuthManager.swift` | Google OAuth 2.0 auth + token management |
| `Services/GoogleHealthClient.swift` | Fetch health data from Google Health API |
| `Models/HealthDataPoint.swift` | Data model for API response |

### Modify (5)

| File | Change |
|---|---|
| `States/AppState.swift` | `FitbitAuthManager` → `GoogleHealthAuthManager` |
| `Controllers/SyncController.swift` | Fitbit API calls → `GoogleHealthClient` |
| `Views/LoginView.swift` | "Sign in with Google" |
| `Views/AccountView.swift` | Google logout |
| `SyncMyFitApp.swift` | Google OAuth redirect handler |

### Delete (1)

| File | Reason |
|---|---|
| `Services/FitbitAuthManager.swift` | Replaced by `GoogleHealthAuthManager` |

### Unchanged (4)

| File | Why |
|---|---|
| `Services/HealthKitManager.swift` | HK writes unchanged |
| `Views/DashboardView.swift` | Grid UI unchanged (only data source swap) |
| `Helpers/KeychainHelper.swift` | Reused as-is |
| `Services/SyncStatusManager.swift` | Last-synced tracking unchanged |

---

## OAuth Flow Diagram

```
┌─────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  iPhone App  │    │ accounts.google  │    │  Google Health   │
│              │    │     .com         │    │   API            │
└──────┬───────┘    └────────┬─────────┘    └────────┬─────────┘
       │                     │                       │
       │  1. Open auth URL   │                       │
       │────────────────────>│                       │
       │                     │                       │
       │  2. User signs in   │                       │
       │  3. Consent screen  │                       │
       │  4. Redirect back   │                       │
       │<────────────────────│                       │
       │                     │                       │
       │  5. Exchange code   │                       │
       │  + client_secret    │                       │
       │────────────────────>│                       │
       │                     │                       │
       │  6. access_token    │                       │
       │  + refresh_token    │                       │
       │<────────────────────│                       │
       │                     │                       │
       │  7. Fetch data      │                       │
       │  (Bearer token)     │                       │
       │────────────────────────────────────────────>│
       │                     │                       │
       │  8. dataPoints[]    │                       │
       │<────────────────────────────────────────────│
       │                     │                       │
       │  9. Write HK        │                       │
       │  samples            │                       │
       └─────────────────────┴───────────────────────┘
```

---

## Post-Migration: Optional Enhancements

These are NOT part of the minimal migration. Add later if desired:

1. **Date-range sync** - "Sync last 7 days" instead of today only
2. **SyncStore cursor** - Track last sync date per data type
3. **Background refresh** - `BGTaskScheduler` for periodic sync
4. **Multi-day batch** - Progress indicator for large date ranges
5. **Workout sync** - Route data, energy, duration (complex)

---

## Testing Checklist

- [ ] Google OAuth login succeeds
- [ ] Tokens stored in Keychain
- [ ] Token refresh works on expiry
- [ ] Steps sync correctly
- [ ] Heart rate sync correctly
- [ ] Sleep sync correctly
- [ ] Calories sync correctly
- [ ] HealthKit samples tagged correctly
- [ ] Duplicate prevention works (delete-before-write)
- [ ] Logout clears all tokens
- [ ] App handles 401 with auto-refresh
- [ ] App handles network errors gracefully
