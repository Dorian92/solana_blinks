# solana_blinks

Native Flutter widgets for Solana Actions and Blinks, with a wallet you can swap out.

> Screenshot placeholder. A short GIF of the example card belongs here.

## Features

- Parses `solana-action:` URLs, dial.to-style `action` query parameters, and `actions.json` rules (`*` and `**`).
- Fetches an action, posts the wallet account, and follows `links.next`.
- Renders a card with text, number, email, URL, date, textarea, select, radio, and checkbox parameters.
- Signs through `BlinkWalletAdapter` only. The card never imports a wallet SDK.
- Confirms the transaction on a Solana RPC after the wallet signs it.

## Platforms

| Platform | How a transaction gets signed |
| --- | --- |
| Android | `MwaWalletAdapter` via Mobile Wallet Adapter (`solana_mobile_client`) |
| iOS | Not available yet. Calls throw `WalletUnsupportedPlatformException`. A later adapter can speak to Solana Mobile's Kotlin clientlib over a Pigeon channel. |
| Any platform, devnet only | `KeypairWalletAdapter`, an in-process Ed25519 signer. Not for production and not for mainnet funds. |

`MwaWalletAdapter` is the only file that imports `solana_mobile_client`. The package barrel exports it, so the web target cannot import `package:solana_blinks/solana_blinks.dart` (`dart:io` comes along with that adapter).

## Install

```yaml
dependencies:
  solana_blinks: ^0.1.0
```

The package needs Dart 3.13 or newer because `solana_kit_rpc` 0.11.0 does.

## Use a card

`BlinkCard` takes the wallet, the action client, and an optional theme. Wrap several cards in `BlinkScope` when they should share one wallet. There is no Provider, Riverpod, or service locator.

```dart
import 'package:flutter/material.dart';
import 'package:solana_blinks/solana_blinks.dart';

class TipPage extends StatelessWidget {
  const TipPage({super.key, required this.wallet});

  final BlinkWalletAdapter wallet;

  @override
  Widget build(BuildContext context) {
    return BlinkCard(
      url: 'solana-action:https://example.com/api/tip',
      adapter: wallet,
      client: ActionClient(),
      rpcUrl: defaultBlinkRpcUrl,
      onSuccess: (signature) {
        debugPrint('confirmed $signature');
      },
    );
  }
}
```

On Android, construct `MwaWalletAdapter` with the identity the wallet should show on the approval sheet, and set `cluster` to `devnet` or `mainnet-beta`. On devnet, `KeypairWalletAdapter()` generates an ephemeral key. Airdrop SOL to `address` before sending.

The example app in `example/` pastes a blink URL, lists three local devnet tips, and toggles between those wallets. `example/server` is a shelf Action server that builds an unsigned devnet SOL transfer with `solana_kit`. Run instructions are in `example/README.md`.

## Write a wallet adapter

Implement `BlinkWalletAdapter`. That interface is the only boundary the card and the executor know about.

```dart
class MyWallet implements BlinkWalletAdapter {
  @override
  String? get publicKey => null;

  @override
  bool get supportsSignAndSend => false;

  @override
  Future<String?> connect() async => null;

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<Uint8List>> signTransactions(List<Uint8List> transactions) {
    throw UnimplementedError('Return the signed wire bytes.');
  }

  @override
  Future<List<String>> signAndSendTransactions(
    List<Uint8List> transactions,
  ) {
    throw const WalletUnknownException('This wallet cannot sign and send.');
  }
}
```

`connect` returns the base58 public key, or `null` when the user dismisses the sheet without a hard failure. Throw a `WalletException` (`WalletUserRejectedException`, `WalletNotConnectedException`, `WalletNotInstalledException`, `WalletUnsupportedPlatformException`, or `WalletUnknownException`) for real failures. When `supportsSignAndSend` is true, the executor skips `sendTransaction` and confirms the signature the wallet returned.

## Security

The Action server builds the transaction. This package base64-decodes those bytes and hands them to the wallet unchanged. It does not decode instructions or rewrite the message. The wallet should show the transaction to the user before it signs. `KeypairWalletAdapter` signs inside the process and will sign whatever the server returned, so keep it on devnet.

## Links

- [Solana Actions and Blinks](https://solana.com/docs/tools/actions)
- [Dialect Blinks documentation](https://docs.dialect.to/blinks)
