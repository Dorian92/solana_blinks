# solana_blinks example

A small app that renders a blink and signs it with either an ephemeral devnet keypair or Android Mobile Wallet Adapter.

The three sample rows all talk to the local tip server in `server/`. Paste any other blink URL into the field to render that instead.

## Run the tip server

From `example/server`:

```bash
dart pub get
dart run bin/server.dart
```

The server listens on `0.0.0.0:8080`.

- `GET /actions.json` maps `/tip` to `/api/tip`
- `GET /api/tip` returns a devnet SOL tip action with an `amount` parameter
- `POST /api/tip?amount=0.001` builds an unsigned legacy transfer with `solana_kit` and returns it base64-encoded

Set `PORT` or `SOLANA_RPC_URL` to override the port and the devnet RPC. The treasury address is printed at startup. It is an example address, not a custodial wallet. The first successful tip creates it. Amounts are limited to `0.001`–`1` SOL so the new account can clear the rent-exempt minimum.

CORS headers follow the Actions spec: `Access-Control-Allow-Origin: *`, methods `GET,POST,PUT,OPTIONS`, and the `Content-Type`, `Authorization`, `Content-Encoding`, and `Accept-Encoding` request headers.

## Run the app

From `example/`:

```bash
flutter pub get
flutter run
```

Start the server first. Then:

1. Leave the wallet toggle on **Keypair (devnet)**.
2. Copy the address under the toggle.
3. Airdrop devnet SOL to that address (`solana airdrop 1 <address> --url devnet`, or a faucet).
4. Open **Local devnet tip**, enter an amount, and send.

A confirmed signature shows a snackbar. **Explorer** opens `https://explorer.solana.com/tx/<signature>?cluster=devnet`.

On an Android emulator, use **Emulator host tip** (`http://10.0.2.2:8080/tip`) so the emulator reaches the server on the host machine. Toggle **Mobile Wallet Adapter** only on a device or emulator that has a wallet installed. That adapter is Android-only; iOS and desktop throw `WalletUnsupportedPlatformException`.

`flutter build web` compiles this app. Mobile Wallet Adapter is imported from `package:solana_blinks/mwa.dart`, and the main `solana_blinks` barrel does not import `dart:io`. On web the adapter throws `WalletUnsupportedPlatformException`; use the keypair toggle there.

`flutter build apk --debug` produces `build/app/outputs/flutter-apk/app-debug.apk`. It needs Android SDK platform 36, build-tools 36.0.0, and NDK 28.2.13676358. `solana_mobile_client` 0.1.2 still declares `compileSdk` 31, and the AndroidX libraries it pulls in require 34 or newer, so `android/build.gradle.kts` raises library compile SDKs to 36. That plugin also applies the Kotlin Gradle plugin itself; Flutter 3.47 warns that a future Flutter release will reject that until the plugin migrates.

There is no Android emulator in this environment, so `flutter run` and a tip signed by a real wallet were not executed. `POST /api/tip` was checked against `https://api.devnet.solana.com` and returned an unsigned transfer.
