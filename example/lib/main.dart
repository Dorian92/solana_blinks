import 'dart:async';

import 'package:flutter/material.dart';
import 'package:solana_blinks/mwa.dart';
import 'package:solana_blinks/solana_blinks.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const BlinksExampleApp());
}

/// Example app that runs a blink against devnet.
class BlinksExampleApp extends StatelessWidget {
  /// Creates the example app.
  const BlinksExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solana Blinks',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9945FF)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

/// One sample blink shown on the home screen.
class SampleBlink {
  /// Creates a sample.
  const SampleBlink({
    required this.title,
    required this.url,
    required this.detail,
  });

  /// Short name.
  final String title;

  /// URL passed to [BlinkCard].
  final String url;

  /// Why this URL is in the list.
  final String detail;
}

/// Sample devnet tips served by `example/server`.
const List<SampleBlink> sampleBlinks = <SampleBlink>[
  SampleBlink(
    title: 'Local devnet tip',
    url: 'http://127.0.0.1:8080/tip',
    detail: 'Website URL. The card loads actions.json from this host.',
  ),
  SampleBlink(
    title: 'Local tip via solana-action',
    url: 'solana-action:http://127.0.0.1:8080/api/tip',
    detail: 'Action URL. Skips the actions.json lookup.',
  ),
  SampleBlink(
    title: 'Emulator host tip',
    url: 'http://10.0.2.2:8080/tip',
    detail: 'Same server, reached from an Android emulator.',
  ),
];

/// Home screen: paste a URL, pick a sample, and choose a wallet.
class HomePage extends StatefulWidget {
  /// Creates the home screen.
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _paste = TextEditingController();
  final ActionClient _client = ActionClient();
  final KeypairWalletAdapter _keypair = KeypairWalletAdapter();
  final MwaWalletAdapter _mwa = MwaWalletAdapter(
    identityUri: Uri.parse('https://github.com/Dorian92/solana_blinks'),
    iconUri: Uri.parse('https://github.com/Dorian92/solana_blinks'),
    identityName: 'solana_blinks example',
    cluster: 'devnet',
  );

  bool _useMwa = false;
  String? _url;
  int _generation = 0;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  void _open(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return;
    }
    setState(() {
      _url = trimmed;
      _generation += 1;
    });
  }

  void _onSuccess(String signature) {
    if (!mounted) {
      return;
    }
    final explorer = Uri.https('explorer.solana.com', '/tx/$signature', {
      'cluster': 'devnet',
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Confirmed. $explorer'),
        action: SnackBarAction(
          label: 'Explorer',
          onPressed: () {
            unawaited(
              launchUrl(explorer, mode: LaunchMode.externalApplication),
            );
          },
        ),
      ),
    );
  }

  void _onError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    final adapter = _useMwa ? _mwa : _keypair;
    return Scaffold(
      appBar: AppBar(title: const Text('Solana Blinks')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _paste,
                  decoration: const InputDecoration(
                    labelText: 'Blink URL',
                    hintText: 'solana-action:https://...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: _open,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => _open(_paste.text),
                  child: const Text('Open'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _useMwa ? 'Mobile Wallet Adapter' : 'Keypair (devnet)',
                  ),
                  subtitle: Text(
                    _useMwa
                        ? 'Android only. iOS and desktop throw an unsupported-platform error.'
                        : 'Ephemeral devnet key. Airdrop SOL to it before sending a tip.',
                  ),
                  value: _useMwa,
                  onChanged: (value) => setState(() => _useMwa = value),
                ),
                if (!_useMwa)
                  SelectableText(
                    _keypair.address,
                    key: const Key('devnet-address'),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Sample devnet blinks',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final sample in sampleBlinks)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(sample.title),
                    subtitle: Text(sample.detail),
                    selected: sample.url == url,
                    onTap: () => _open(sample.url),
                  ),
              ],
            ),
          ),
          if (url != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: BlinkCard(
                  key: ValueKey('$_useMwa|$url|$_generation'),
                  url: url,
                  adapter: adapter,
                  client: _client,
                  rpcUrl: defaultBlinkRpcUrl,
                  onSuccess: _onSuccess,
                  onError: _onError,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
