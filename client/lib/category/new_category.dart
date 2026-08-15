import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'category.dart';

class NewCategory extends ConsumerStatefulWidget {
  const NewCategory({
    super.key,
    required this.onAddCategory,
    this.initialCategory,
  });

  final Category? initialCategory;
  final void Function(Category category) onAddCategory;

  @override
  ConsumerState<NewCategory> createState() => _NewCategoryState();
}

class _NewCategoryState extends ConsumerState<NewCategory> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  late IconData _selectedIcon;
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      _titleController.text = widget.initialCategory!.title;
      _descriptionController.text =
          widget.initialCategory!.description.toString();
      _selectedIcon = widget.initialCategory!.icon;
      _selectedColor = widget.initialCategory!.color;
    } else {
      _selectedIcon = Icons.work_outline;
      _selectedColor = Colors.black;
    }
  }

  void _submitCategoryData() {
    if (_titleController.text.trim().isEmpty) {
      showDialog(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Invalid input'),
              content: const Text(
                'Please make sure a valid title was entered.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                  child: const Text('Okay'),
                ),
              ],
            ),
      );
      return;
    }

    widget.onAddCategory(
      Category(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        icon: _selectedIcon,
        color: _selectedColor,
      ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Column(
        children: [
          TextField(
            controller: _titleController,
            maxLength: 50,
            decoration: const InputDecoration(label: Text('Title')),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            maxLength: 500,
            decoration: const InputDecoration(label: Text('Description')),
            minLines: 3,
            maxLines: 5,
          ),
          SizedBox(height: 16),
          GridView(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisExtent: 50,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            children:
                selectableCategoryColors
                    .map(
                      (c) => InkWell(
                        onTap:
                            () => setState(() {
                              _selectedColor = c;
                            }),
                        child: Container(
                          margin: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  _selectedColor == c
                                      ? Colors.black
                                      : Colors.transparent,
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
                  selectableCategoryIcons
                      .map(
                        (c) => InkWell(
                          onTap:
                              () => setState(() {
                                _selectedIcon = c.icon;
                              }),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _selectedColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    _selectedIcon == c.icon
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              c.icon,
                              size: 30,
                              color:
                                  _selectedColor.computeLuminance() > 0.5
                                      ? Colors.black
                                      : Colors.white,
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _submitCategoryData,
                child: const Text('Save Category'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
