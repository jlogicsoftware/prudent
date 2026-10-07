import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/categories.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import 'category_color_swatch.dart';
import 'category_icon_choice.dart';
import 'category_icons.dart';

/// Shared create/edit form. The caller decides whether the result becomes a
/// [CreateCategoryRequest] or an [UpdateCategoryRequest] — both carry the same four fields, so
/// this widget stays agnostic between them and just hands back the values.
class NewCategory extends StatefulWidget {
  const NewCategory({super.key, required this.onSave, this.initialCategory});

  final Category? initialCategory;
  final void Function({
    required String title,
    required String iconKey,
    required String description,
    required int colorArgb,
  })
  onSave;

  @override
  State<NewCategory> createState() => _NewCategoryState();
}

class _NewCategoryState extends State<NewCategory> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  late String _selectedIconKey;
  late int _selectedColorArgb;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCategory;
    if (initial != null) {
      _titleController.text = initial.title;
      _descriptionController.text = initial.description;
      _selectedIconKey = initial.iconKey;
      _selectedColorArgb = initial.colorArgb;
    } else {
      _selectedIconKey = prudentCategoryIcons.keys.first;
      _selectedColorArgb = Colors.black.toARGB32();
    }
  }

  void _submit() {
    if (_titleController.text.trim().isEmpty) {
      final t = PrudentLocalizations.of(context);
      showDialog(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Text(t.invalidInputTitle),
              content: Text(t.categoryInvalidInput),
              actions: [
                ZenButton(label: t.okay, variant: ZenButtonVariant.text, onPressed: () => Navigator.pop(ctx)),
              ],
            ),
      );
      return;
    }

    widget.onSave(
      title: _titleController.text.trim(),
      iconKey: _selectedIconKey,
      description: _descriptionController.text.trim(),
      colorArgb: _selectedColorArgb,
    );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final selectedColor = Color(_selectedColorArgb);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          children: [
            ZenTextField(
              label: t.categoryTitleField,
              controller: _titleController,
              maxLength: 50,
            ),
            const SizedBox(height: 16),
            ZenTextField(
              label: t.categoryDescriptionField,
              controller: _descriptionController,
              maxLength: 500,
              minLines: 3,
              maxLines: 5,
            ),
            const SizedBox(height: 16),
            GridView(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisExtent: 50,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              children: [
                for (final c in prudentCategoryColors)
                  CategoryColorSwatch(
                    color: c,
                    selected: c.toARGB32() == _selectedColorArgb,
                    onTap: () => setState(() => _selectedColorArgb = c.toARGB32()),
                  ),
              ],
            ),
            Container(
              height: 200,
              margin: const EdgeInsets.only(top: 16, bottom: 16),
              child: GridView(
                shrinkWrap: true,
                // The viewport clips what overflows it, and a FocusRing sits 4px outside its
                // control; without room the first and last rows' rings would be cut off.
                padding: const EdgeInsets.all(4),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisExtent: 50,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                children: [
                  for (final entry in prudentCategoryIcons.entries)
                    CategoryIconChoice(
                      icon: entry.value,
                      color: selectedColor,
                      selected: _selectedIconKey == entry.key,
                      onTap: () => setState(() => _selectedIconKey = entry.key),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                ZenButton(
                  label: t.cancel,
                  variant: ZenButtonVariant.text,
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                ZenButton(label: t.categorySave, onPressed: _submit),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
