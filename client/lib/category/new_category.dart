import 'package:flutter/material.dart';

import '../src/generated/prudent/v1/categories.pb.dart';
import '../src/l10n/generated/prudent_localizations.dart';
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
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.okay))],
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
      child: Column(
        children: [
          TextField(
            controller: _titleController,
            maxLength: 50,
            decoration: InputDecoration(label: Text(t.categoryTitleField)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            maxLength: 500,
            decoration: InputDecoration(label: Text(t.categoryDescriptionField)),
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
            children:
                prudentCategoryColors
                    .map(
                      (c) => InkWell(
                        onTap: () => setState(() => _selectedColorArgb = c.toARGB32()),
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c.toARGB32() == _selectedColorArgb ? Colors.black : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
          Container(
            height: 200,
            margin: const EdgeInsets.only(top: 16, bottom: 16),
            child: GridView(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisExtent: 50,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              children:
                  prudentCategoryIcons.entries
                      .map(
                        (entry) => InkWell(
                          onTap: () => setState(() => _selectedIconKey = entry.key),
                          child: Container(
                            decoration: BoxDecoration(
                              color: selectedColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    _selectedIconKey == entry.key
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              entry.value,
                              size: 30,
                              color: selectedColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          Row(
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
              const Spacer(),
              ElevatedButton(onPressed: _submit, child: Text(t.categorySave)),
            ],
          ),
        ],
      ),
    );
  }
}
