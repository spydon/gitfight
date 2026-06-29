import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The landing overlay where the user types a public repository URL.
class RepoEntry extends StatefulWidget {
  const RepoEntry({
    required this.error,
    required this.launches,
    required this.onSubmit,
    super.key,
  });

  final ValueListenable<String?> error;
  final ValueListenable<int?> launches;
  final ValueChanged<String> onSubmit;

  @override
  State<RepoEntry> createState() => _RepoEntryState();
}

class _RepoEntryState extends State<RepoEntry> {
  static final _conferenceUrl = Uri.parse('https://flutterfriends.dev');

  final _controller = TextEditingController(
    text: 'https://github.com/flame-engine/flame',
  );
  final _conferenceTap = TapGestureRecognizer();
  final _urlTap = TapGestureRecognizer();

  @override
  void initState() {
    super.initState();
    void open() =>
        launchUrl(_conferenceUrl, mode: LaunchMode.externalApplication);
    _conferenceTap.onTap = open;
    _urlTap.onTap = open;
  }

  void _submit() => widget.onSubmit(_controller.text);

  @override
  void dispose() {
    _controller.dispose();
    _conferenceTap.dispose();
    _urlTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(28),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xCC0B1020),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2C5A82)),
            boxShadow: const [
              BoxShadow(color: Color(0x886FB1E0), blurRadius: 40),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Git Fight',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEAF6FF),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Replay any public repo as a space battle. Each committer '
                'flies in when they first appear, then fires at neighbours '
                'who commit around the same time, or at the planet when '
                'working solo.',
                style: TextStyle(color: Color(0xFF9FB3C8), height: 1.4),
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<String?>(
                valueListenable: widget.error,
                builder: (_, error, _) => TextField(
                  controller: _controller,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Repository URL',
                    hintText: 'github.com / gitlab.com / bitbucket.org',
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.rocket_launch),
                  label: const Text('Launch'),
                ),
              ),
              const SizedBox(height: 20),
              const Divider(color: Color(0x332C5A82)),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: Color(0xFF9FB3C8),
                    height: 1.5,
                    fontSize: 13,
                  ),
                  children: [
                    const TextSpan(
                      text:
                          'Built with Flutter, Flame and Supabase. Coming to ',
                    ),
                    TextSpan(
                      text: 'Flutter & Friends',
                      recognizer: _conferenceTap,
                      style: const TextStyle(
                        color: Color(0xFF6FB1E0),
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF6FB1E0),
                      ),
                    ),
                    const TextSpan(
                      text:
                          ', the friendliest Flutter conference in Stockholm? '
                          'Use discount code ',
                    ),
                    const TextSpan(
                      text: 'COMMUNITY10',
                      style: TextStyle(
                        color: Color(0xFFFFD166),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const TextSpan(text: ' at '),
                    TextSpan(
                      text: 'flutterfriends.dev',
                      recognizer: _urlTap,
                      style: const TextStyle(
                        color: Color(0xFF6FB1E0),
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF6FB1E0),
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: ValueListenableBuilder<int?>(
                  valueListenable: widget.launches,
                  builder: (_, count, _) => Text(
                    count == null ? '' : '🚀 launched $count times',
                    style: const TextStyle(
                      color: Color(0xFF6E7E92),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
