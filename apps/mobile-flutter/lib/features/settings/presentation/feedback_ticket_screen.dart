import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/top_snack.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/logging/vpn_core_layout.dart';
import '../../../services/logging/vpn_logger.dart';
import '../../../services/remote/console_feedback.dart';
import '../../auth/domain/auth_controller.dart';
import 'settings_picker_sheet.dart';

class FeedbackTicketScreen extends ConsumerStatefulWidget {
  const FeedbackTicketScreen({super.key});

  @override
  ConsumerState<FeedbackTicketScreen> createState() =>
      _FeedbackTicketScreenState();
}

class _FeedbackTicketScreenState extends ConsumerState<FeedbackTicketScreen> {
  static const _maxImages = 5;

  final _emailCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _otherTypeCtrl = TextEditingController();

  String _type = 'software_bug';
  String _severity = 'medium';
  final List<File> _images = [];
  bool _submitting = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _descriptionCtrl.dispose();
    _otherTypeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountFeedbackTicket)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildPickerTile(
            context,
            title: l10n.ticketTypeLabel,
            value: _typeLabel(_type, l10n),
            onTap: () => _pickType(context, l10n),
          ),
          if (_type == 'other') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _otherTypeCtrl,
              decoration: InputDecoration(
                labelText: l10n.ticketTypeOtherHint,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildPickerTile(
            context,
            title: l10n.ticketSeverityLabel,
            value: _severityLabel(_severity, l10n),
            onTap: () => _pickSeverity(context, l10n),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            decoration: InputDecoration(
              labelText: l10n.ticketContactEmail,
              hintText: l10n.ticketContactEmailHint,
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionCtrl,
            decoration: InputDecoration(
              labelText: l10n.ticketDescription,
            ),
            minLines: 4,
            maxLines: 8,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.ticketImagesLimit(_maxImages),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._images.map(
                (file) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        file,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: () => setState(() => _images.remove(file)),
                        icon: const Icon(Icons.close, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
              if (_images.length < _maxImages)
                OutlinedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(l10n.ticketAddImages),
                ),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _submitting ? null : () => _submit(l10n),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.ticketSubmit),
          ),
        ],
      ),
    );
  }

  Widget _buildPickerTile(
    BuildContext context, {
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(value),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Future<void> _pickType(BuildContext context, AppLocalizations l10n) async {
    final result = await SettingsPickerSheet.show<String>(
      context: context,
      title: l10n.ticketTypeLabel,
      options: [
        SettingsPickerOption(value: 'page_bug', label: l10n.ticketTypePageBug),
        SettingsPickerOption(
          value: 'software_bug',
          label: l10n.ticketTypeSoftwareBug,
        ),
        SettingsPickerOption(value: 'other', label: l10n.ticketTypeOther),
      ],
      currentValue: _type,
      isSelected: (a, b) => a == b,
    );
    if (result != null) setState(() => _type = result);
  }

  Future<void> _pickSeverity(BuildContext context, AppLocalizations l10n) async {
    final result = await SettingsPickerSheet.show<String>(
      context: context,
      title: l10n.ticketSeverityLabel,
      options: [
        SettingsPickerOption(value: 'low', label: l10n.ticketSeverityLow),
        SettingsPickerOption(value: 'medium', label: l10n.ticketSeverityMedium),
        SettingsPickerOption(value: 'high', label: l10n.ticketSeverityHigh),
        SettingsPickerOption(
          value: 'critical',
          label: l10n.ticketSeverityCritical,
        ),
      ],
      currentValue: _severity,
      isSelected: (a, b) => a == b,
    );
    if (result != null) setState(() => _severity = result);
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null) return;
    setState(() {
      for (final file in result.files) {
        if (_images.length >= _maxImages) break;
        final path = file.path;
        if (path != null) _images.add(File(path));
      }
    });
  }

  Future<void> _submit(AppLocalizations l10n) async {
    final session = ref.read(authControllerProvider).session;
    if (session == null) return;
    final description = _descriptionCtrl.text.trim();
    if (description.isEmpty) {
      showTopSnackBar(context, l10n.ticketDescriptionRequired, isError: true);
      return;
    }
    if (_type == 'other' && _otherTypeCtrl.text.trim().isEmpty) {
      showTopSnackBar(context, l10n.ticketTypeOtherHint, isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final typeLabel = _type == 'other'
          ? _otherTypeCtrl.text.trim()
          : _typeLabel(_type, l10n);
      // 工单附带运行日志（此前工单完全不带日志）；图片不再 Base64 进日志字段（会乱码），仅计数。
      final vpnLog = await ref.read(vpnLoggerProvider).buildFeedbackSnapshot(
            window: VpnCoreLayout.manualFeedbackWindow,
          );
      await ConsoleFeedback().submitTicket(
        session: session,
        type: typeLabel,
        severity: _severity,
        description: description,
        contactEmail: _emailCtrl.text.trim(),
        images: _images,
        vpnLog: vpnLog,
      );
      if (!mounted) return;
      showTopSnackBar(context, l10n.ticketSubmitted);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, '$e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _typeLabel(String type, AppLocalizations l10n) {
    return switch (type) {
      'page_bug' => l10n.ticketTypePageBug,
      'software_bug' => l10n.ticketTypeSoftwareBug,
      'other' => l10n.ticketTypeOther,
      _ => type,
    };
  }

  String _severityLabel(String severity, AppLocalizations l10n) {
    return switch (severity) {
      'low' => l10n.ticketSeverityLow,
      'medium' => l10n.ticketSeverityMedium,
      'high' => l10n.ticketSeverityHigh,
      'critical' => l10n.ticketSeverityCritical,
      _ => severity,
    };
  }
}
