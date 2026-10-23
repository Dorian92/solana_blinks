## 0.1.0

* Solana Actions models, a blink link parser, and an `ActionClient` for GET, POST, and `links.next`, with no Flutter imports in the core.
* `BlinkWalletAdapter` is the only wallet boundary. `MwaWalletAdapter` talks to Mobile Wallet Adapter on Android. `KeypairWalletAdapter` is a devnet-only in-process signer.
* `TransactionExecutor` submits a signed transaction with `solana_kit` and polls until it is confirmed. It does not modify the server's transaction.
* `BlinkCard`, `BlinkController`, and `BlinkScope` render an action and share a wallet without a state-management package.
* Depends on `http`, the `solana_kit` modules this package calls, and `solana_mobile_client` 0.1.2. Requires Dart 3.13 because `solana_kit_rpc` 0.11.0 does.
