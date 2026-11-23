
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:expense_tracker/data/api/expense_api.dart';
import 'package:expense_tracker/data/models/models.dart';
import 'package:expense_tracker/state/app_state.dart';
import 'package:expense_tracker/features/categories/categories_page.dart';
import 'package:expense_tracker/core/widgets/common.dart';

/// Add or edit a transaction. Pops `true` when something was saved.
class TransactionFormPage extends StatefulWidget {
  const TransactionFormPage({super.key, this.transaction});
  final Transaction? transaction;

  @override
  State<TransactionFormPage> createState() => _TransactionFormPageState();
}

class _TransactionFormPageState extends State<TransactionFormPage> {
  final _form = GlobalKey<FormState>();
  final _state = AppState.instance;
  late final _amount = TextEditingController(
      text: widget.transaction == null ? '' : widget.transaction!.amount.toStringAsFixed(2));
  late final _note = TextEditingController(text: widget.transaction?.note ?? '');

  late TxType _type = widget.transaction?.type ?? TxType.expense;
  late String? _categoryId = widget.transaction?.categoryId;
  late DateTime _date = widget.transaction?.date ?? DateUtils.dateOnly(DateTime.now());
  late bool _hasReceipt = widget.transaction?.hasReceipt ?? false;

  // receipt chosen but not uploaded yet (new transactions)
  Uint8List? _pendingReceipt;
  String? _pendingName;

  bool _saving = false;
  bool _receiptBusy = false;
  bool _changed = false; // receipt changes on an existing row count as saved

  bool get _isEdit => widget.transaction != null;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  static final _amountPattern = RegExp(r'^\d{1,10}([.,]\d{1,2})?$');

  String? _validateAmount(String? v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return 'Enter an amount';
    if (!_amountPattern.hasMatch(text)) return 'Use a number with up to 2 decimals';
    if (double.parse(text.replaceAll(',', '.')) <= 0) return 'Amount must be greater than 0';
    return null;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final amount = double.parse(_amount.text.trim().replaceAll(',', '.'));
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    try {
      final Transaction saved = _isEdit
          ? await ExpenseApi.updateTransaction(widget.transaction!.id,
              type: _type, amount: amount, date: _date, categoryId: _categoryId, note: note)
          : await ExpenseApi.createTransaction(
              type: _type, amount: amount, date: _date, categoryId: _categoryId, note: note);

      if (_pendingReceipt != null) {
        try {
          await ExpenseApi.uploadReceipt(saved.id, _pendingReceipt!, _pendingName ?? 'receipt.jpg');
        } catch (e) {
          if (mounted) showMessage(context, 'Saved, but the receipt failed to upload: ${errorText(e)}', error: true);
        }
      }
      if (!mounted) return;
      showMessage(context, _isEdit ? 'Transaction updated.' : 'Transaction added.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context, title: 'Delete transaction?', message: 'This cannot be undone.');
    if (!ok) return;
    setState(() => _saving = true);
    try {
      await ExpenseApi.deleteTransaction(widget.transaction!.id);
      if (!mounted) return;
      showMessage(context, 'Transaction deleted.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  // ---------------------------------------------------------------- receipt

  Future<void> _pickReceipt() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    } on PlatformException catch (e) {
      if (mounted) showMessage(context, 'Could not open ${source.name}: ${e.message ?? e.code}', error: true);
      return;
    }
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) showMessage(context, 'The image must be smaller than 5 MB.', error: true);
      return;
    }
    if (!_isEdit) {
      setState(() {
        _pendingReceipt = bytes;
        _pendingName = file!.name;
      });
      return;
    }
    setState(() => _receiptBusy = true);
    try {
      await ExpenseApi.uploadReceipt(widget.transaction!.id, bytes, file.name);
      if (!mounted) return;
      setState(() {
        _hasReceipt = true;
        _changed = true;
      });
      showMessage(context, 'Receipt saved.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _receiptBusy = false);
    }
  }

  Future<void> _viewReceipt() async {
    if (_pendingReceipt != null) {
      return _showImage(Image.memory(_pendingReceipt!));
    }
    setState(() => _receiptBusy = true);
    try {
      final url = await ExpenseApi.receiptUrl(widget.transaction!.id);
      if (!mounted) return;
      await _showImage(Image.network(url, errorBuilder: (_, _, _) => _openExternally(url)));
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _receiptBusy = false);
    }
  }

  /// PDFs (or anything Flutter cannot draw) open in the browser instead.
  Widget _openExternally(String url) => Padding(
        padding: const EdgeInsets.all(24),
        child: FilledButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open receipt'),
          onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        ),
      );

  Future<void> _showImage(Widget image) => showDialog(
        context: context,
        builder: (ctx) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: InteractiveViewer(child: image)),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ]),
        ),
      );

  Future<void> _removeReceipt() async {
    if (_pendingReceipt != null) {
      setState(() => _pendingReceipt = null);
      return;
    }
    final ok = await confirm(context, title: 'Remove receipt?', message: 'The photo will be deleted.', action: 'Remove');
    if (!ok) return;
    setState(() => _receiptBusy = true);
    try {
      await ExpenseApi.removeReceipt(widget.transaction!.id);
      if (!mounted) return;
      setState(() {
        _hasReceipt = false;
        _changed = true;
      });
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _receiptBusy = false);
    }
  }

  Future<void> _manageCategories() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CategoriesPage(initialType: _type)));
    if (mounted) setState(() {}); // categories may have changed
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final categories = _state.categoriesOf(_type);
    if (_categoryId != null && !categories.any((c) => c.id == _categoryId)) _categoryId = null;
    final hasReceipt = _hasReceipt || _pendingReceipt != null;

    return PopScope(
      canPop: !_saving,
      onPopInvokedWithResult: (didPop, _) {
        // receipt-only changes on an existing transaction were already saved
        if (didPop && _changed) _state.dataChanged();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit transaction' : 'New transaction'),
          actions: [
            if (_isEdit)
              IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _saving ? null : _delete),
          ],
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<TxType>(
                segments: const [
                  ButtonSegment(value: TxType.expense, label: Text('Expense'), icon: Icon(Icons.arrow_upward)),
                  ButtonSegment(value: TxType.income, label: Text('Income'), icon: Icon(Icons.arrow_downward)),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() {
                  _type = v.first;
                  _categoryId = null; // categories differ per type
                }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                autofocus: !_isEdit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                style: Theme.of(context).textTheme.headlineSmall,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '${_state.currency} ',
                  border: const OutlineInputBorder(),
                ),
                validator: _validateAmount,
              ),
              const SizedBox(height: 20),
              Row(children: [
                Text('Category', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton(onPressed: _manageCategories, child: const Text('Manage')),
              ]),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in categories)
                  ChoiceChip(
                    avatar: Icon(iconFor(c.icon), size: 18, color: hexColor(c.color)),
                    label: Text(c.name),
                    selected: _categoryId == c.id,
                    onSelected: (sel) => setState(() => _categoryId = sel ? c.id : null),
                  ),
                if (categories.isEmpty) const Text('No categories yet — tap Manage to add one.'),
              ]),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Date'),
                subtitle: Text(DateFormat.yMMMMEEEEd().format(_date)),
                onTap: _pickDate,
                trailing: const Icon(Icons.chevron_right),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _note,
                maxLength: 500,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.notes),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: _receiptBusy
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(hasReceipt ? Icons.receipt : Icons.add_a_photo_outlined),
                  title: Text(hasReceipt ? 'Receipt attached' : 'Add a receipt photo'),
                  subtitle: _pendingReceipt != null ? const Text('Will be uploaded when you save') : null,
                  onTap: _receiptBusy ? null : (hasReceipt ? _viewReceipt : _pickReceipt),
                  trailing: hasReceipt && !_receiptBusy
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: 'Replace', icon: const Icon(Icons.sync), onPressed: _pickReceipt),
                          IconButton(tooltip: 'Remove', icon: const Icon(Icons.close), onPressed: _removeReceipt),
                        ])
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? 'Save changes' : 'Add transaction'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
