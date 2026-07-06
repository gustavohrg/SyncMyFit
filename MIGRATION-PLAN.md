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

## Phased Implementation

### Phase 0: Prerequisites (Manual Setup)

**Goal:** Google Cloud project ready, credentials in hand. No code changes.

| Step | Task | Done |
|---|---|---|
| 0.1 | Create Google Cloud project (or use existing) | [ ] |
| 0.2 | Enable **Google Health API** in API Library | [ ] |
| 0.3 | Create OAuth 2.0 Client ID (type: Web Server) | [ ] |
| 0.4 | Set redirect URI to `https://www.google.com` | [ ] |
| 0.5 | Copy Client ID + Client Secret | [ ] |
| 0.6 | Add test user email in Audience page | [ ] |
| 0.7 | Add scopes: `googlehealth.activity_and_fitness` | [ ] |

**Exit criteria:** You have a valid `client_id` and `client_secret` from Google Console.

---

### Phase 1: Auth Layer (Google OAuth) ✅ DONE

**Goal:** App logs in via Google instead of Fitbit. Token exchange and refresh work.

**Files:**

| Action | File |
|---|---|
| Create | `Services/GoogleHealthAuthManager.swift` |
| Create | `SyncMyFit/Secrets.swift` (gitignored) |
| Create | `SyncMyFit/Secrets.plist` (gitignored) |
| Modify | `States/AppState.swift` |
| Modify | `Views/LoginView.swift` |
| Modify | `Views/AccountView.swift` |
| Modify | `Controllers/SyncController.swift` |
| Modify | `SyncMyFitApp.swift` |
| Modify | `SyncMyFit.xcodeproj/project.pbxproj` |
| Delete | `Services/FitbitAuthManager.swift` |

**Tasks:**

| Step | Task | Done |
|---|---|---|
| 1.1 | Update `Secrets.plist` with `GoogleClientID` + `GoogleClientSecret` | [x] |
| 1.2 | Create `GoogleHealthAuthManager.swift` with Google OAuth flow | [x] |
| 1.3 | Implement `startLogin()` → `ASWebAuthenticationSession` to `accounts.google.com` | [x] |
| 1.4 | Implement `fetchAccessToken()` → POST to `oauth2.googleapis.com/token` | [x] |
| 1.5 | Implement `refreshAccessToken()` → POST to `oauth2.googleapis.com/token` | [x] |
| 1.6 | Implement `performAuthenticatedRequest()` with auto-refresh on 401 | [x] |
| 1.7 | Implement `isTokenValid()`, `logout()`, Keychain storage | [x] |
| 1.8 | Update `AppState.swift` → replace `FitbitAuthManager` refs | [x] |
| 1.9 | Update `LoginView.swift` → "Sign in with Google" | [x] |
| 1.10 | Update `SyncMyFitApp.swift` → Google OAuth redirect handler | [x] |
| 1.11 | Delete `FitbitAuthManager.swift` | [x] |

**Key implementation details:**
- Auth URL: `https://accounts.google.com/o/oauth2/v2/auth?client_id=...&redirect_uri=...&response_type=code&scope=...&access_type=offline`
- Token exchange needs `client_secret` (not just PKCE like Fitbit)
- No PKCE required (client_secret provides proof)
- Keychain keys: change from `fitbit_access_token` / `fitbit_refresh_token` to `google_access_token` / `google_refresh_token`

**Exit criteria:** App launches, shows "Sign in with Google", completes OAuth, stores tokens. Dashboard can load (even if data fetch still hits Fitbit endpoints temporarily).

**Findings:**
- Google Health API `getProfile` only returns age + membership start date. Display name + avatar requires People API with `userinfo.profile` scope.
- AccountView.swift now fetches profile from `people.googleapis.com/v1/people/me?personFields=names,photos`
- Google OAuth requires `client_secret` (unlike Fitbit PKCE). For sideloaded app, this is acceptable.
- Redirect URI format: reversed client ID `com.googleusercontent.apps.{client_id_encoded}`
- Xcode project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+) - files auto-added, no manual pbxproj edits needed for new files.
- Had to remove explicit Secrets.swift/plist references from pbxproj to avoid duplicate build commands.
- `SyncController.swift` updated to use `GoogleHealthAuthManager.shared` for authenticated requests (data endpoints still Fitbit - Phase 2 task).

---

### Phase 2: Data Layer (Google Health API Client) ✅ DONE

**Goal:** Fetch health data from Google Health API instead of Fitbit API.

**Files:**

| Action | File |
|---|---|
| Create | `Models/HealthDataPoint.swift` |
| Create | `Services/GoogleHealthClient.swift` |
| Modify | `Controllers/SyncController.swift` |
| Modify | `Views/DashboardView.swift` |

**Tasks:**

| Step | Task | Done |
|---|---|---|
| 2.1 | Create `HealthDataPoint.swift` data model | [x] |
| 2.2 | Create `GoogleHealthClient.swift` | [x] |
| 2.3 | Implement `fetchSteps(since:to:)` → `GET /v4/users/me/dataTypes/steps/dataPoints` | [x] |
| 2.4 | Implement `fetchHeartRate(since:to:)` → `GET /v4/users/me/dataTypes/heart-rate/dataPoints` | [x] |
| 2.5 | Implement `fetchSleep(since:to:)` → `GET /v4/users/me/dataTypes/sleep/dataPoints` | [x] |
| 2.6 | Implement `fetchCalories(since:to:)` → `GET /v4/users/me/dataTypes/active-energy-burned/dataPoints` | [x] |
| 2.7 | Implement `fetchProfile()` → `GET /v1/people/me?personFields=names` | [x] |
| 2.8 | Update `SyncController.swift` → replace Fitbit fetch calls with `GoogleHealthClient` | [x] |

**Key implementation details:**
- Base URL: `https://health.googleapis.com/v4`
- Auth header: `Bearer {access_token}`
- Query params: `startTime` (ISO 8601), `endTime` (ISO 8601)
- Response: `{ "dataPoints": [{ "startTime": "...", "endTime": "...", "value": ... }] }`
- Uses `GoogleHealthAuthManager.shared.performAuthenticatedRequest()` for all calls
- Sleep data type is `sleep` (not `sleep_session`)
- Calories data type is `active-energy-burned` (not `total-calories`)
- `HealthDataPoint` has helper extensions: `stepsValue`, `heartRateBPM`, `sleepHours`, `caloriesValue`
- Fallback raw JSON parser included for when Codable decoding fails

**Findings:**
- Google Health API sleep data type is `sleep` (Session type), not `sleep_session`
- Calories: `active-energy-burned` for active calories, `total-calories` for read-only derived total
- `fetchSleepData` return type changed from `Result<[String: Any], Error>` to `Result<Double, Error>` (simpler)
- DashboardView.swift needed update at line 234 to match new sleep return type
- All Fitbit API URLs removed from codebase

**Key implementation details:**
- Base URL: `https://health.googleapis.com`
- Auth header: `Bearer {access_token}`
- Query params: `startTime` (RFC 3339), `endTime` (RFC 3339)
- Response: `{ "dataPoints": [{ "startTime": "...", "endTime": "...", "value": ... }] }`
- Use `GoogleHealthAuthManager.shared.performAuthenticatedRequest()` for all calls

**Exit criteria:** Sync button fetches real data from Google Health API and displays on dashboard. Build succeeds.

---

### Phase 3: HealthKit Tagging Update ✅ DONE

**Goal:** HealthKit samples tagged as "Google Health" instead of "Fitbit".

**Files:**

| Action | File |
|---|---|
| Modify | `Services/HealthKitManager.swift` |

**Tasks:**

| Step | Task | Done |
|---|---|---|
| 3.1 | Update `metadata["SyncSource"]` from `"Fitbit"` to `"Google Health"` in all write methods | [x] |
| 3.2 | Update `deleteExistingSamples()` filter to match new metadata value | [x] |

**Findings:**
- Simple string replacement: 4 metadata dictionaries + 1 filter
- Old "Fitbit" samples remain in HealthKit (user can delete manually if desired)
- New samples will be tagged "Google Health" and deduped correctly

**Exit criteria:** New samples tagged "Google Health". Old "Fitbit" samples left in place (user can delete manually if desired).

---

### Phase 4: UI Polish + Cleanup ✅ DONE

**Goal:** All UI references updated, no Fitbit branding remaining.

**Files:**

| Action | File |
|---|---|
| Modify | `Views/AccountView.swift` |
| Modify | `Views/DashboardView.swift` |
| Modify | `README.md` |
| Modify | `SyncMyFit.xcodeproj/project.pbxproj` |

**Tasks:**

| Step | Task | Done |
|---|---|---|
| 4.1 | Update `AccountView.swift` logout to use `GoogleHealthAuthManager` | [x] (done in Phase 1) |
| 4.2 | Update `README.md` setup instructions for Google Cloud | [x] |
| 4.3 | Update Fitbit comment in `DashboardView.swift` | [x] |
| 4.4 | Update `INFOPLIST_KEY_NSHealthShareUsageDescription` in pbxproj | [x] |

**Findings:**
- `GoogleHealthAuthManager.swift` comment "Created on migration from Fitbit" kept as historical note
- `MIGRATION-PLAN.md` references to Fitbit are documentation context, not active code
- README updated to version 2.0.0, all setup instructions now reference Google Cloud

---

### Phase 5: Testing

**Goal:** Verify everything works end-to-end.

| Step | Task | Done |
|---|---|---|
| 5.1 | Google OAuth login succeeds | [ ] |
| 5.2 | Tokens stored in Keychain | [ ] |
| 5.3 | Token refresh works on expiry | [ ] |
| 5.4 | Steps sync correctly | [ ] |
| 5.5 | Heart rate sync correctly | [ ] |
| 5.6 | Sleep sync correctly | [ ] |
| 5.7 | Calories sync correctly | [ ] |
| 5.8 | HealthKit samples tagged "Google Health" | [ ] |
| 5.9 | Duplicate prevention works (delete-before-write) | [ ] |
| 5.10 | Logout clears all tokens | [ ] |
| 5.11 | App handles 401 with auto-refresh | [ ] |
| 5.12 | App handles network errors gracefully | [ ] |

---

## File Summary

### Create (5)

| File | Phase | Purpose |
|---|---|---|
| `Services/GoogleHealthAuthManager.swift` | 1 | Google OAuth 2.0 auth + token management |
| `Models/HealthDataPoint.swift` | 2 | Data model for Google Health API response |
| `Services/GoogleHealthClient.swift` | 2 | Fetch health data from Google Health API |
| `SyncMyFit/Secrets.swift` | 1 | Credentials loader (gitignored) |
| `SyncMyFit/Secrets.plist` | 1 | Google OAuth credentials (gitignored) |

### Modify (8)

| File | Phase | Change |
|---|---|---|
| `States/AppState.swift` | 1 | `FitbitAuthManager` → `GoogleHealthAuthManager` |
| `Views/LoginView.swift` | 1 | "Sign in with Google" + Google-colored dots |
| `Views/AccountView.swift` | 1 | Google People API profile fetch |
| `SyncMyFitApp.swift` | 1 | Google OAuth redirect handler |
| `Controllers/SyncController.swift` | 2 | Fitbit API → `GoogleHealthClient` |
| `Views/DashboardView.swift` | 2 | Updated sleep return type |
| `Services/HealthKitManager.swift` | 3 | Metadata tagging update |
| `SyncMyFit.xcodeproj/project.pbxproj` | 1 | Remove duplicate Secrets refs |

### Delete (1)

| File | Phase | Reason |
|---|---|---|
| `Services/FitbitAuthManager.swift` | 1 | Replaced by `GoogleHealthAuthManager` |

### Unchanged (3)

| File | Why |
|---|---|
| `Helpers/KeychainHelper.swift` | Reused as-is |
| `Services/SyncStatusManager.swift` | Last-synced tracking unchanged |
| `Views/DashboardView.swift` | Grid UI unchanged (data source swap handled in SyncController) |

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
