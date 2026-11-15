import 'dart:developer' as developer;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../account/account_edit.dart';
import '../generated/prudent/v1/accounts.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../load_error_view.dart';
import '../providers.dart';
import 'import_failure.dart';
import 'import_failure_view.dart';
import 'import_providers.dart';
import 'open_import_sessions.dart';
import 'statement_format.dart';
import 'statement_picker.dart';

/// The first step of an import (M6, jlogicsoftware/prudent#74): choose the account the statement is
/// for and the CSV file, and upload it for checking. [onOpenReview] then shows what was found; this
/// widget never navigates, so both steps stay inside the one page `ImportStatementScreen` is.
///
/// Only active accounts are offered, and an account without a bank account number is refused here
/// with a way to add the number: the server compares the statement's own account with it and refuses
/// an account that has none (ADR-090), so asking now saves a round trip that can only fail.
class ImportUploadStep extends ConsumerStatefulWidget {
  const ImportUploadStep({super.key, required this.onOpenReview});

  /// Opens the review of the session with this id: the one just created, or an unfinished one.
  final void Function(String sessionId) onOpenReview;

  @override
  ConsumerState<ImportUploadStep> createState() => _ImportUploadStepState();
}

class _ImportUploadStepState extends ConsumerState<ImportUploadStep> {
  String? _accountId;
  PickedStatement? _file;
  String? _fileProblem;
  ImportFailure? _failure;
  var _busy = false;

  Future<void> _choose() async {
    final t = PrudentLocalizations.of(context);
    try {
      final picked = await ref.read(statementPickerProvider)();
      if (picked == null || !mounted) return;
      setState(() {
        _failure = null;
        if (picked.bytes.isEmpty) {
          _file = null;
          _fileProblem = t.importFileEmpty;
        } else if (picked.bytes.length > maxStatementBytes) {
          _file = null;
          _fileProblem = t.importFileTooLarge;
        } else {
          _file = picked;
          _fileProblem = null;
        }
      });
    } on StatementTooLarge {
      if (!mounted) return;
      setState(() {
        _file = null;
        _fileProblem = t.importFileTooLarge;
      });
    } catch (error, stack) {
      // Only the failure's type is logged: whatever the platform put in its message could name the
      // file, and the file is the user's.
      developer.log(
        'Could not read the chosen statement file (${error.runtimeType}).',
        name: 'prudent',
        level: 1000,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() {
        _file = null;
        _fileProblem = t.importFileReadFailed;
      });
    }
  }

  Future<void> _upload(String accountId) async {
    final file = _file;
    if (file == null) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final session = await ref
          .read(importStarterProvider)
          .start(bytes: file.bytes, accountId: accountId);
      if (!mounted) return;
      widget.onOpenReview(session.id);
    } on ZenError catch (error) {
      ref.invalidate(openImportSessionsProvider);
      if (!mounted) return;
      setState(() => _failure = ImportFailure.from(error, creating: true));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _editAccount(Account account) {
    showAdaptivePresentation<void>(
      context,
      builder:
          (_) => AccountEdit(
            account: account,
            onSave:
                (request) => ref.read(accountsProvider.notifier).editAccount(account.id, request),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider);

    return ZenPageScaffold(
      title: t.importTitle,
      body: accounts.when(
        loading: () => const Center(child: ZenProgressIndicator()),
        error:
            (error, stack) => LoadErrorView(
              message: t.accountsLoadError,
              error: error,
              stackTrace: stack,
              onRetry: () => ref.invalidate(accountsProvider),
            ),
        data: (all) {
          final active = [
            for (final a in all)
              if (a.isActive) a,
          ];
          final selectedId =
              _accountId != null && active.any((a) => a.id == _accountId)
                  ? _accountId
                  : (active.length == 1 ? active.first.id : null);
          final selected = active.where((a) => a.id == selectedId).firstOrNull;
          final numberMissing = selected != null && selected.accountNumber.trim().isEmpty;
          final canUpload = selected != null && !numberMissing && _file != null && !_busy;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(t.importIntro, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              if (active.isEmpty)
                Text(t.importNoActiveAccounts, style: theme.textTheme.bodyLarge)
              else
                ZenSelect<String>(
                  label: t.importAccountField,
                  items: [for (final a in active) a.id],
                  itemLabel: (id) => active.firstWhere((a) => a.id == id).name,
                  value: selectedId,
                  onChanged: (id) => setState(() {
                    _accountId = id;
                    _failure = null;
                  }),
                ),
              if (numberMissing) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.importAccountNumberMissing,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ZenButton(
                          label: t.importAddAccountNumber,
                          variant: ZenButtonVariant.secondary,
                          icon: Icons.edit_outlined,
                          onPressed: () => _editAccount(selected),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                _file == null ? t.importNoFile : t.importFileChosen(_file!.name),
                style: theme.textTheme.bodyMedium,
              ),
              if (_fileProblem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _fileProblem!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ZenButton(
                  label: _file == null ? t.importChooseFile : t.importChangeFile,
                  variant: ZenButtonVariant.secondary,
                  icon: Icons.upload_file,
                  onPressed: _busy ? null : _choose,
                ),
              ),
              const SizedBox(height: 16),
              if (_failure != null) ...[
                ImportFailureView(failure: _failure!, title: t.importFailureTitle),
                const SizedBox(height: 16),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: ZenButton(
                  label: t.importUpload,
                  isLoading: _busy,
                  onPressed: canUpload ? () => _upload(selected.id) : null,
                ),
              ),
              OpenImportSessions(onContinue: widget.onOpenReview),
            ],
          );
        },
      ),
    );
  }
}
