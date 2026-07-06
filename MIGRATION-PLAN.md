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

### Phase 1: Auth Layer (Google OAuth)

**Goal:** App logs in via Google instead of Fitbit. Token exchange and refresh work.

**Files:**

| Action | File |
|---|---|
| Create | `Services/GoogleHealthAuthManager.swift` |
| Modify | `States/AppState.swift` |
| Modify | `Views/LoginView.swift` |
| Modify | `SyncMyFitApp.swift` |
| Delete | `Services/FitbitAuthManager.swift` |

**Tasks:**

| Step | Task | Done |
|---|---|---|
| 1.1 | Update `Secrets.plist` with `GoogleClientID` + `GoogleClientSecret` | [ ] |
| 1.2 | Create `GoogleHealthAuthManager.swift` with Google OAuth flow | [ ] |
| 1.3 | Implement `startLogin()` → `ASWebAuthenticationSession` to `accounts.google.com` | [ ] |
| 1.4 | Implement `fetchAccessToken()` → POST to `oauth2.googleapis.com/token` | [ ] |
| 1.5 | Implement `refreshAccessToken()` → POST to `oauth2.googleapis.com/token` | [ ] |
| 1.6 | Implement `performAuthenticatedRequest()` with auto-refresh on 401 | [ ] |
| 1.7 | Implement `isTokenValid()`, `logout()`, Keychain storage | [ ] |
| 1.8 | Update `AppState.swift` → replace `FitbitAuthManager` refs | [ ] |
| 1.9 | Update `LoginView.swift` → "Sign in with Google" | [ ] |
| 1.10 | Update `SyncMyFitApp.swift` → Google OAuth redirect handler | [ ] |
| 1.11 | Delete `FitbitAuthManager.swift` | [ ] |

**Key implementation details:**
- Auth URL: `https://accounts.google.com/o/oauth2/v2/auth?client_id=...&redirect_uri=...&response_type=code&scope=...&access_type=offline`
- Token exchange needs `client_secret` (not just PKCE like Fitbit)
- No PKCE required (client_secret provides proof)
- Keychain keys: change from `fitbit_access_token` / `fitbit_refresh_token` to `google_access_token` / `google_refresh_token`

**Exit criteria:** App launches, shows "Sign in with Google", completes OAuth, stores tokens. Dashboard can load (even if data fetch still hits Fitbit endpoints temporarily).

---

### Phase 2: Data Layer (Google Health API Client)

**Goal:** Fetch health data from Google Health API instead of Fitbit API.

**Files:**

| Action | File |
|---|---|
| Create | `Models/HealthDataPoint.swift` |
| Create | `Services/GoogleHealthClient.swift` |
| Modify | `Controllers/SyncController.swift` |

**Tasks:**

| Step | Task | Done |
|---|---|---|
| 2.1 | Create `HealthDataPoint.swift` data model | [ ] |
| 2.2 | Create `GoogleHealthClient.swift` | [ ] |
| 2.3 | Implement `fetchSteps(since:to:)` → `GET /v4/users/me/dataTypes/steps/dataPoints` | [ ] |
| 2.4 | Implement `fetchHeartRate(since:to:)` → `GET /v4/users/me/dataTypes/heart_rate/dataPoints` | [ ] |
| 2.5 | Implement `fetchSleep(since:to:)` → `GET /v4/users/me/dataTypes/sleep_session/dataPoints` | [ ] |
| 2.6 | Implement `fetchCalories(since:to:)` → `GET /v4/users/me/dataTypes/total_calories/dataPoints` | [ ] |
| 2.7 | Implement `fetchProfile()` → `GET /v4/users/me/profile` | [ ] |
| 2.8 | Update `SyncController.swift` → replace Fitbit fetch calls with `GoogleHealthClient` | [ ] |

**Key implementation details:**
- Base URL: `https://health.googleapis.com`
- Auth header: `Bearer {access_token}`
- Query params: `startTime` (RFC 3339), `endTime` (RFC 3339)
- Response: `{ "dataPoints": [{ "startTime": "...", "endTime": "...", "value": ... }] }`
- Use `GoogleHealthAuthManager.shared.performAuthenticatedRequest()` for all calls

**Exit criteria:** Sync button fetches real data from Google Health API and displays on dashboard.

---

### Phase 3: HealthKit Tagging Update

**Goal:** HealthKit samples tagged as "Google Health" instead of "Fitbit".

**Files:**

| Action | File |
|---|---|
| Modify | `Services/HealthKitManager.swift` |

**Tasks:**

| Step | Task | Done |
|---|---|---|
| 3.1 | Update `metadata["SyncSource"]` from `"Fitbit"` to `"Google Health"` in all write methods | [ ] |
| 3.2 | Update `deleteExistingSamples()` filter to match new metadata value | [ ] |

**Exit criteria:** New samples tagged "Google Health". Old "Fitbit" samples left in place (user can delete manually if desired).

---

### Phase 4: UI Polish + Cleanup

**Goal:** All UI references updated, no Fitbit branding remaining.

**Files:**

| Action | File |
|---|---|
| Modify | `Views/AccountView.swift` |
| Modify | `README.md` |

**Tasks:**

| Step | Task | Done |
|---|---|---|
| 4.1 | Update `AccountView.swift` logout to use `GoogleHealthAuthManager` | [ ] |
| 4.2 | Update `README.md` setup instructions for Google Cloud | [ ] |
| 4.3 | Remove `Secrets.plist` Fitbit key references from code comments | [ ] |
| 4.4 | Search codebase for any remaining "Fitbit" strings, update as needed | [ ] |

**Exit criteria:** No Fitbit references remain. App is fully Google Health.

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

### Create (3)

| File | Phase | Purpose |
|---|---|---|
| `Services/GoogleHealthAuthManager.swift` | 1 | Google OAuth 2.0 auth + token management |
| `Models/HealthDataPoint.swift` | 2 | Data model for API response |
| `Services/GoogleHealthClient.swift` | 2 | Fetch health data from Google Health API |

### Modify (6)

| File | Phase | Change |
|---|---|---|
| `States/AppState.swift` | 1 | `FitbitAuthManager` → `GoogleHealthAuthManager` |
| `Views/LoginView.swift` | 1 | "Sign in with Google" |
| `SyncMyFitApp.swift` | 1 | Google OAuth redirect handler |
| `Controllers/SyncController.swift` | 2 | Fitbit API calls → `GoogleHealthClient` |
| `Services/HealthKitManager.swift` | 3 | Metadata tagging update |
| `Views/AccountView.swift` | 4 | Google logout |

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
