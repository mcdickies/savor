# Shared Gemini API Key Setup

Follow these steps to publish a single Gemini API key that every user in the app can use. The instructions are split into three short sections so you always know where the key lives, what the app expects, and the minimum code that has to be in your build.

## 1. Keep the Placeholder in the Bundle

* File: `yummr/GeminiSecrets.plist`
* Current value: `THIS-IS-THE-KEY`
* Purpose: a last-resort fallback if the Firestore document and the local keychain are both empty.

> ✅ Leave the placeholder in place and **do not** check your real key into source control. The bundle fallback keeps the app from crashing but isn’t meant for production use.

## 2. Publish the Shared Key in Firestore

1. Open the Firebase console → **Firestore Database** → stay on the **Data** tab.
2. Create the collection `appConfig` if it doesn’t exist yet.
3. Inside `appConfig`, add a document with the ID `publicSecrets`.
4. Add a **string** field named `geminiAPIKey` and paste your real Gemini key as the value. You can use the placeholder `"YOUR-REAL-KEY"` while testing the flow.
5. Click **Save**. You should now see the path `appConfig / publicSecrets` with the `geminiAPIKey` field displayed.
6. Back in the app, open **Settings → AI Drafting** and tap **Reload shared key** so the client downloads and caches the new value.

What happens behind the scenes:

* `SecretsService.resolveSharedGeminiAPIKey()` requests `appConfig/publicSecrets`.
* On success, the service stores the key in the keychain for fast reuse.
* `AIRecipeService` uses the cached key when generating drafts.

If Firestore doesn’t have the document yet, the Settings screen shows a placeholder and drafting fails gracefully.

## 3. Minimum Code & Rules Required

Make sure these pieces are included in your build so the Firestore lookup works:

* `yummr/SecretsService.swift` — fetches `/appConfig/publicSecrets` and caches the key.
* `yummr/AIRecipeService.swift` (updated `loadAPIKey()`) — calls the secrets service before trying the bundled plist or environment variable.
* `yummr/SettingsView.swift` — shows the shared key status and provides the **Reload shared key** button.
* `firebase/firestore.rules` — allows public read access to `/appConfig/**` while keeping writes locked down.
* `firebase/storage.rules` — publish these Firestore Storeage rules so signed-in users can upload profile and post media.
* `yummr/GeminiSecrets.plist` — keep the `THIS-IS-THE-KEY` placeholder as a reminder and fallback.

Once those files and the Firestore document are in place, every signed-in user automatically receives the same Gemini API key from Firestore without exposing the secret in your repo.
