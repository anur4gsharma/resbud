import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../data/auth_session_manager.dart';
import '../../shared/design_tokens.dart';
import '../generation/generation_api_client.dart';

class AuthSessionDialog extends StatefulWidget {
  const AuthSessionDialog({
    super.key,
    required this.authManager,
  });

  final AuthSessionManager authManager;

  static Future<void> show(BuildContext context, AuthSessionManager authManager) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => AuthSessionDialog(authManager: authManager),
      );

  @override
  State<AuthSessionDialog> createState() => _AuthSessionDialogState();
}

class _AuthSessionDialogState extends State<AuthSessionDialog> {
  late final TextEditingController _tokenController;
  bool _testingConnection = false;
  String? _connectionStatus;
  bool? _connectionHealthy;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.authManager.token ?? '');
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _connectionStatus = null;
      _connectionHealthy = null;
    });

    final baseUrl = GenerationApiClient.defaultBaseUrl;
    try {
      final readyUri = Uri.parse(baseUrl).resolve('/health/ready');
      final res = await http.get(readyUri).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _connectionHealthy = true;
          _connectionStatus = 'Connected to production backend ($baseUrl)\nStatus: Ready';
        });
      } else {
        setState(() {
          _connectionHealthy = false;
          _connectionStatus = 'Server returned HTTP ${res.statusCode}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectionHealthy = false;
        _connectionStatus = 'Connection failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _testingConnection = false);
      }
    }
  }

  Future<void> _saveToken() async {
    final text = _tokenController.text.trim();
    await widget.authManager.setToken(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text.isEmpty ? 'Session token cleared.' : 'Session token saved.'),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.authManager.tokenInfo;
    final hasToken = widget.authManager.hasToken;
    final isExpired = info?.isExpired ?? false;

    return Padding(
      padding: EdgeInsets.only(
        left: ResbudDesignTokens.pagePadding,
        right: ResbudDesignTokens.pagePadding,
        top: ResbudDesignTokens.pagePadding,
        bottom: MediaQuery.of(context).viewInsets.bottom + ResbudDesignTokens.pagePadding,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.security, color: ResbudDesignTokens.primaryLight),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Backend & Session Authorization',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(128),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Server Endpoint:',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      GenerationApiClient.defaultBaseUrl,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _testingConnection ? null : _testConnection,
                          icon: _testingConnection
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.wifi_tethering, size: 16),
                          label: const Text('Test Connection'),
                        ),
                      ],
                    ),
                    if (_connectionStatus != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _connectionStatus!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _connectionHealthy == true ? Colors.green.shade700 : Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'JWT Bearer Token',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Protected production endpoints require a valid JWT issued by your identity provider.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (hasToken)
              Card(
                color: isExpired
                    ? Colors.red.shade50
                    : Colors.green.shade50,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Icon(
                        isExpired ? Icons.warning_amber : Icons.check_circle_outline,
                        color: isExpired ? Colors.red.shade800 : Colors.green.shade800,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isExpired ? 'Session Expired' : 'Session Active',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isExpired ? Colors.red.shade900 : Colors.green.shade900,
                              ),
                            ),
                            if (info?.subject != null)
                              Text('User: ${info!.subject}', style: const TextStyle(fontSize: 12)),
                            if (info?.expiresAt != null)
                              Text(
                                isExpired ? 'Expired: ${info!.expiresAt}' : 'Expires: ${info!.expiresAt}',
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _tokenController.clear();
                          _saveToken();
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Paste Bearer JWT Token',
                border: OutlineInputBorder(),
                hintText: 'eyJhbGciOi...',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saveToken,
                  child: const Text('Save Token'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
