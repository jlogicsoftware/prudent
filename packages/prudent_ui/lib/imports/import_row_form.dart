import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../category/selectable_categories.dart';
import '../generated/prudent/v1/categories.pb.dart';
import '../generated/prudent/v1/imports.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import 'import_failure.dart';
import 'import_failure_text.dart';
import 'import_review.dart';

/// Category and note for one row before it is confirmed. Only the categories that can file the
/// row's direction are offered (an expense category cannot file income and the reverse), and an
/// archived one is not, as in the record form.
///
/// [onSave] sends only what changed and throws the server's error when it is refused; the form
/// shows that error in words and stays open, so a refusal is never swallowed and nothing is lost.
class ImportRowForm extends StatefulWidget {
  const ImportRowForm({
    super.key,
    required this.row,
    required this.categories,
    required this.onSave,
  });

  final ImportRow row;
  final List<Category> categories;
  final Future<void> Function({String? categoryId, String? note}) onSave;

  @override
  State<ImportRowForm> createState() => _ImportRowFormState();
}

class _ImportRowFormState extends State<ImportRowForm> {
  late String _categoryId = widget.row.hasCategoryId() ? widget.row.categoryId : '';
  late final _note = TextEditingController(text: widget.row.hasNote() ? widget.row.note : '');
  String? _error;
  var _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = PrudentLocalizations.of(context);
    final originalCategory = widget.row.hasCategoryId() ? widget.row.categoryId : '';
    final originalNote = widget.row.hasNote() ? widget.row.note : '';
    final note = _note.text.trim();
    if (note.runes.length > 500) {
      setState(() => _error = t.importRowNoteTooLong);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        categoryId: _categoryId == originalCategory ? null : _categoryId,
        note: note == originalNote ? null : note,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '${t.importRowSaveFailed} ${importFailureMessage(t, ImportFailure.from(error))}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final offered = selectableCategories(
      widget.categories,
      keep: _categoryId.isEmpty ? null : _categoryId,
      expense: ImportReview.isExpense(widget.row),
    );
    final names = {for (final c in offered) c.id: c.title};
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              t.importRowEditTitle(widget.row.rowNumber),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 16),
          ZenSelect<String>(
            label: t.importRowCategoryField,
            items: ['', ...names.keys],
            itemLabel: (id) => id.isEmpty ? t.importNoCategory : names[id] ?? t.importNoCategory,
            value: names.containsKey(_categoryId) ? _categoryId : '',
            onChanged: _saving ? null : (id) => setState(() => _categoryId = id),
          ),
          const SizedBox(height: 16),
          ZenTextField(
            label: t.importRowNoteField,
            controller: _note,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            enabled: !_saving,
          ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ZenButton(label: t.importRowSave, isLoading: _saving, onPressed: _save),
              ZenButton(
                label: t.cancel,
                variant: ZenButtonVariant.text,
                onPressed: _saving ? null : () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
