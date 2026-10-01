# OUI-APEX app

Flutter app (iOS, macOS, Android) that controls OUI-APEX firmware over Bluetooth LE. Features and boards: see the [main README](../README.md).

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release      # or ipa / macos
```

Code layout: `lib/core` (BLE protocol, state, database, GPS), `lib/features` (screens), `lib/widgets` (shared UI).
