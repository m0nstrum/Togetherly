import '../dict_strings.dart' show ruEn; // fork: accessible action labels
import '../fork/ui/feedback.dart'; // fork (PLAN 2.2)
import 'package:flutter/material.dart';
import '../models/pair_data.dart';
import '../models/relationship_status.dart';
import '../services/locale_service.dart';
import '../theme/theme_scope.dart';
import '../widgets/app_sheet.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/m3_loading.dart';

class RelationshipStatusScreen extends StatefulWidget {
  final PairData pairData;

  const RelationshipStatusScreen({super.key, required this.pairData});

  @override
  State<RelationshipStatusScreen> createState() =>
      _RelationshipStatusScreenState();
}

class _RelationshipStatusScreenState extends State<RelationshipStatusScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.pairData.addListener(_onPairChanged);
  }

  @override
  void dispose() {
    widget.pairData.removeListener(_onPairChanged);
    super.dispose();
  }

  void _onPairChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final connection = widget.pairData.manager.activeConnection;
    if (connection == null) {
      return Scaffold(
        appBar: AppBar(title: Text(LocaleService.current.relationshipStatus)),
        body: Center(child: Text(LocaleService.current.noActiveConnection)),
      );
    }

    final currentStatus = connection.currentStatus;
    final t = context.appTheme;

    return Scaffold(
      backgroundColor: t.surfaceMuted,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: ruEn('Назад', 'Back'),
          icon: Icon(Icons.arrow_back, color: t.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          LocaleService.current.relationshipStatus,
          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? Center(
              child: M3Loading(color: Theme.of(context).colorScheme.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Current Status Card
                  _buildCurrentStatusCard(currentStatus),
                  const SizedBox(height: 24),

                  // Predefined Statuses
                  _buildSectionTitle(LocaleService.current.chooseAStatus),
                  const SizedBox(height: 12),
                  ...RelationshipStatus.predefinedStatuses.map(
                    (status) => _buildStatusTile(
                      status,
                      isSelected: currentStatus?.id == status.id,
                      onTap: () => _setStatus(status),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Custom Statuses
                  _buildSectionTitle(LocaleService.current.customStatuses),
                  const SizedBox(height: 12),
                  ...connection.customStatuses.map(
                    (status) => _buildStatusTile(
                      status,
                      isSelected: currentStatus?.id == status.id,
                      isCustom: true,
                      onTap: () => _setStatus(status),
                      onEdit: () => _editCustomStatus(status),
                      onDelete: () => _deleteCustomStatus(status),
                    ),
                  ),

                  const SizedBox(height: 12),
                  _buildAddCustomButton(),
                  const SizedBox(height: 24),

                  // Clear Status Button
                  if (currentStatus != null) _buildClearStatusButton(),
                ],
              ),
            ),
    );
  }

  Widget _buildCurrentStatusCard(RelationshipStatus? status) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.tertiaryContainer],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            LocaleService.current.currentStatus,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(status?.emoji ?? '—', style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text(
            status?.label ?? LocaleService.current.notSet,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: cs.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final t = context.appTheme;
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: t.textPrimary,
      ),
    );
  }

  Widget _buildStatusTile(
    RelationshipStatus status, {
    required bool isSelected,
    bool isCustom = false,
    VoidCallback? onTap,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    final t = context.appTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer
            : t.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Theme.of(context).colorScheme.primary : t.divider,
          width: 2,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Text(status.emoji, style: const TextStyle(fontSize: 28)),
        title: Text(
          status.label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: t.textPrimary,
          ),
        ),
        trailing: isCustom
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected)
                    Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  if (isSelected) const SizedBox(width: 8),
                  IconButton(
                    tooltip: ruEn('Изменить', 'Edit'),
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: onEdit,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  IconButton(
                    tooltip: ruEn('Удалить', 'Delete'),
                    icon: const Icon(Icons.delete, size: 20),
                    onPressed: onDelete,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ],
              )
            : isSelected
            ? Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              )
            : null,
      ),
    );
  }

  Widget _buildAddCustomButton() {
    final t = context.appTheme;
    return OutlinedButton.icon(
      onPressed: _addCustomStatus,
      icon: const Icon(Icons.add),
      label: Text(LocaleService.current.addCustomStatus),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: BorderSide(color: t.divider, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildClearStatusButton() {
    final t = context.appTheme;
    return ElevatedButton(
      onPressed: _clearStatus,
      style: ElevatedButton.styleFrom(
        backgroundColor: t.surfaceMuted,
        foregroundColor: t.textPrimary,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        LocaleService.current.clearStatus,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _setStatus(RelationshipStatus status) async {
    setState(() => _loading = true);
    try {
      await widget.pairData.manager.activeConnection?.setStatus(status);
      if (mounted) {
        AppSnack.success(
          context,
          LocaleService.current.statusSetTo(status.label),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, ForkFailure.of(e).text);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearStatus() async {
    setState(() => _loading = true);
    try {
      await widget.pairData.manager.activeConnection?.clearStatus();
      if (mounted) {
        AppSnack.success(context, LocaleService.current.statusCleared);
      }
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, ForkFailure.of(e).text);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCustomStatus() async {
    final result = await showAppSheet<Map<String, String>>(
      context,
      builder: (_) => const _CustomStatusSheet(),
    );

    if (result != null && mounted) {
      setState(() => _loading = true);
      try {
        await widget.pairData.manager.activeConnection?.addCustomStatus(
          result['label']!,
          result['emoji']!,
        );
        if (mounted) {
          AppSnack.success(context, LocaleService.current.customStatusAdded);
        }
      } catch (e) {
        if (mounted) {
          AppSnack.error(context, ForkFailure.of(e).text);
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<void> _editCustomStatus(RelationshipStatus status) async {
    final result = await showAppSheet<Map<String, String>>(
      context,
      builder: (_) => _CustomStatusSheet(
        initialLabel: status.label,
        initialEmoji: status.emoji,
        isEdit: true,
      ),
    );

    if (result != null && mounted) {
      setState(() => _loading = true);
      try {
        await widget.pairData.manager.activeConnection?.updateCustomStatus(
          status.id,
          result['label']!,
          result['emoji']!,
        );
        if (mounted) {
          AppSnack.success(context, LocaleService.current.statusUpdated);
        }
      } catch (e) {
        if (mounted) {
          AppSnack.error(context, ForkFailure.of(e).text);
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<void> _deleteCustomStatus(RelationshipStatus status) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: LocaleService.current.deleteStatus,
      message: LocaleService.current.deleteStatusConfirm(status.label),
      confirmLabel: LocaleService.current.delete,
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );

    if (confirmed && mounted) {
      setState(() => _loading = true);
      try {
        await widget.pairData.manager.activeConnection?.deleteCustomStatus(
          status.id,
        );
        if (mounted) {
          AppSnack.success(context, LocaleService.current.statusDeleted);
        }
      } catch (e) {
        if (mounted) {
          AppSnack.error(context, ForkFailure.of(e).text);
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }
}

// Dialog for adding/editing custom status
class _CustomStatusSheet extends StatefulWidget {
  final String initialLabel;
  final String initialEmoji;
  final bool isEdit;

  const _CustomStatusSheet({
    this.initialLabel = '',
    this.initialEmoji = '',
    this.isEdit = false,
  });

  @override
  State<_CustomStatusSheet> createState() => _CustomStatusSheetState();
}

class _CustomStatusSheetState extends State<_CustomStatusSheet> {
  late TextEditingController _labelController;
  late TextEditingController _emojiController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.initialLabel);
    _emojiController = TextEditingController(text: widget.initialEmoji);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SheetScaffold(
      title: widget.isEdit
          ? LocaleService.current.editStatus
          : LocaleService.current.addCustomStatus,
      bottom: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(LocaleService.current.cancel),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                final label = _labelController.text.trim();
                final emoji = _emojiController.text.trim();
                if (label.isNotEmpty) {
                  Navigator.pop(context, {'label': label, 'emoji': emoji});
                }
              },
              child: Text(
                widget.isEdit
                    ? LocaleService.current.update
                    : LocaleService.current.add,
              ),
            ),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _emojiController,
              decoration: InputDecoration(
                labelText: LocaleService.current.emojiLabel,
                hintText: LocaleService.current.emojiHint,
              ),
              maxLength: 2,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _labelController,
              decoration: InputDecoration(
                labelText: LocaleService.current.labelField,
                hintText: LocaleService.current.egLivingTogether,
              ),
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
      ),
    );
  }
}
