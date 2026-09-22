import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/legal_content.dart';

/// Tabs of the legal dialog: Contact (1st), Terms (2nd), Privacy (3rd).
enum LegalTab { contact, terms, privacy }

Future<void> showLegalDialog(
  BuildContext context, {
  LegalTab initialTab = LegalTab.contact,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => LegalDialog(initialTab: initialTab),
  );
}

class LegalDialog extends StatelessWidget {
  const LegalDialog({super.key, this.initialTab = LegalTab.contact});

  final LegalTab initialTab;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PASAKAY Legal'),
      content: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: DefaultTabController(
          length: 3,
          initialIndex: initialTab.index,
          child: const Column(
            children: [
              TabBar(
                labelColor: AppColors.primary,
                tabs: [
                  Tab(text: 'Contact'),
                  Tab(text: 'Terms'),
                  Tab(text: 'Privacy'),
                ],
              ),
              SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children: [
                    _ContactTab(),
                    _LegalTextTab(
                      effectiveDate: LegalContent.effectiveDate,
                      sections: LegalContent.terms,
                    ),
                    _LegalTextTab(
                      effectiveDate: LegalContent.effectiveDate,
                      sections: LegalContent.privacy,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ContactTab extends StatelessWidget {
  const _ContactTab();

  Future<void> _email(BuildContext context) async {
    final uri = Uri.parse(
      'mailto:${LegalContent.contactEmail}?subject=${Uri.encodeComponent('PASAKAY Concern')}',
    );
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Fall through to copy-to-clipboard.
    }
    if (!context.mounted) return;
    await Clipboard.setData(
      const ClipboardData(text: LegalContent.contactEmail),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Email address copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contact Administrator',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            LegalContent.contactIntro,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            LegalContent.contactEmail,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _email(context),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Email us'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      const ClipboardData(text: LegalContent.contactEmail),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Email address copied to clipboard.'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegalTextTab extends StatelessWidget {
  const _LegalTextTab({required this.effectiveDate, required this.sections});

  final String effectiveDate;
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Text(
          'Effective Date: $effectiveDate',
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.textSecondary,
            fontStyle: FontStyle.italic,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        for (final section in sections) ...[
          Text(
            section.title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            section.body,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

/// The three consent checkboxes required before creating an account
/// (Terms & Conditions User Consent section).
class ConsentCheckboxes extends StatefulWidget {
  const ConsentCheckboxes({super.key, required this.onChanged});

  /// Called with true only when all three boxes are checked.
  final ValueChanged<bool> onChanged;

  @override
  State<ConsentCheckboxes> createState() => _ConsentCheckboxesState();
}

class _ConsentCheckboxesState extends State<ConsentCheckboxes> {
  bool _terms = false;
  bool _privacy = false;
  bool _data = false;
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => showLegalDialog(context, initialTab: LegalTab.terms);
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => showLegalDialog(context, initialTab: LegalTab.privacy);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  void _notify() => widget.onChanged(_terms && _privacy && _data);

  TextStyle get _body => GoogleFonts.plusJakartaSans(
        color: AppColors.textSecondary,
        fontSize: 13,
        height: 1.35,
      );

  TextStyle get _link => GoogleFonts.plusJakartaSans(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _box(
          value: _terms,
          onChanged: (v) => setState(() {
            _terms = v;
            _notify();
          }),
          label: Text.rich(
            TextSpan(
              text: 'I have read and agree to the PASAKAY ',
              style: _body,
              children: [
                TextSpan(
                  text: 'Terms and Conditions.',
                  style: _link,
                  recognizer: _termsTap,
                ),
              ],
            ),
          ),
        ),
        _box(
          value: _privacy,
          onChanged: (v) => setState(() {
            _privacy = v;
            _notify();
          }),
          label: Text.rich(
            TextSpan(
              text: 'I have read and understood the PASAKAY ',
              style: _body,
              children: [
                TextSpan(
                  text: 'Privacy Policy.',
                  style: _link,
                  recognizer: _privacyTap,
                ),
              ],
            ),
          ),
        ),
        _box(
          value: _data,
          onChanged: (v) => setState(() {
            _data = v;
            _notify();
          }),
          label: Text(
            'I voluntarily consent to the collection, processing, storage, '
            'and use of my personal information for the operation and '
            'evaluation of PASAKAY in accordance with the Data Privacy Act '
            'of 2012 (Republic Act No. 10173).',
            style: _body,
          ),
        ),
      ],
    );
  }

  Widget _box({
    required bool value,
    required ValueChanged<bool> onChanged,
    required Widget label,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          activeColor: AppColors.primary,
          checkColor: Colors.white,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          onChanged: (v) => onChanged(v ?? false),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 9, bottom: 9),
            child: label,
          ),
        ),
      ],
    );
  }
}
