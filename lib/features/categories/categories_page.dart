import 'package:flutter/material.dart';

import 'package:expense_tracker/data/api/expense_api.dart';
import 'package:expense_tracker/data/models/models.dart';
import 'package:expense_tracker/state/app_state.dart';
import 'package:expense_tracker/core/widgets/common.dart';

/// Add, rename, recolour and delete categories (two tabs: expense / income).
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, this.initialType = TxType.expense});
  final TxType initialType;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final _state = AppState.instance;

  Future<void> _edit({Category? category, required TxType type}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryEditor(category: category, type: type),
    );
    if (changed == true) {
      await _state.reloadCategories().catchError((_) {});
      _state.dataChanged();
    }
  }

  Future<void> _delete(Category c) async {
    final others = _state.categoriesOf(c.type).where((x) => x.id != c.id).toList();
    // null = keep transactions without a category
    String? moveTo;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Delete "${c.name}"?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('What should happen to its transactions?'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: moveTo,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Transactions'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Keep them as "Uncategorized"')),
                for (final o in others)
                  DropdownMenuItem(value: o.id, child: Text('Move to ${o.name}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setLocal(() => moveTo = v),
            ),
            const SizedBox(height: 8),
            Text('A budget for this category will also be removed.',
                style: Theme.of(ctx).textTheme.bodySmall),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final affected = await ExpenseApi.deleteCategory(c.id, reassignTo: moveTo);
      await _state.reloadCategories();
      _state.dataChanged();
      if (mounted) {
        showMessage(context,
            affected == 0 ? 'Category deleted.' : 'Category deleted. $affected transaction(s) updated.');
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialType == TxType.income ? 1 : 0,
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Categories'),
            bottom: const TabBar(tabs: [Tab(text: 'Expenses'), Tab(text: 'Income')]),
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Add category',
            onPressed: () => _edit(
                type: DefaultTabController.of(context).index == 1 ? TxType.income : TxType.expense),
            child: const Icon(Icons.add),
          ),
          body: ListenableBuilder(
            listenable: _state,
            builder: (context, _) => TabBarView(children: [
              for (final type in TxType.values.reversed) _list(type), // expense, income
            ]),
          ),
        );
      }),
    );
  }

  Widget _list(TxType type) {
    final items = _state.categoriesOf(type);
    if (items.isEmpty) {
      return const EmptyView(icon: Icons.category_outlined, title: 'No categories', subtitle: 'Tap + to add one.');
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (_, i) {
        final c = items[i];
        return ListTile(
          leading: CategoryAvatar(icon: c.icon, color: c.color),
          title: Text(c.name),
          onTap: () => _edit(category: c, type: type),
          trailing: IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(c),
          ),
        );
      },
    );
  }
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({this.category, required this.type});
  final Category? category;
  final TxType type;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late String _icon = widget.category?.icon ?? 'category';
  late String _color = widget.category?.color ?? categoryColors.first;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Enter a name');
    if (name.length > 40) return setState(() => _error = 'Use at most 40 characters');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.category == null) {
        await ExpenseApi.createCategory(name: name, type: widget.type, icon: _icon, color: _color);
      } else {
        await ExpenseApi.updateCategory(widget.category!.id, name: name, icon: _icon, color: _color);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            widget.category == null
                ? 'New ${widget.type == TxType.income ? 'income' : 'expense'} category'
                : 'Edit category',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: widget.category == null,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: 'Name',
              border: const OutlineInputBorder(),
              errorText: _error,
              prefixIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: CategoryAvatar(icon: _icon, color: _color, size: 32),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          Text('Icon', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final entry in categoryIcons.entries)
              IconButton.outlined(
                isSelected: _icon == entry.key,
                icon: Icon(entry.value),
                onPressed: () => setState(() => _icon = entry.key),
              ),
          ]),
          const SizedBox(height: 16),
          Text('Colour', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final hex in categoryColors)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _color = hex),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: hexColor(hex),
                  child: _color.toUpperCase() == hex ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                ),
              ),
          ]),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ]),
      ),
    );
  }
}
