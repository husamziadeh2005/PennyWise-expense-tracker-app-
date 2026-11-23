import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:expense_tracker/core/network/api_client.dart';
import 'package:expense_tracker/data/api/expense_api.dart';
import 'package:expense_tracker/features/auth/auth_service.dart';
import 'package:expense_tracker/features/auth/auth_validators.dart';
import 'package:expense_tracker/data/models/models.dart';
import 'package:expense_tracker/state/app_state.dart';
import 'package:expense_tracker/features/categories/categories_page.dart';
import 'package:expense_tracker/core/widgets/common.dart';

const countries = ['Jordan', 'Saudi Arabia', 'United Arab Emirates', 'United States', 'Other'];
const currencies = ['JOD', 'SAR', 'AED', 'USD', 'EUR', 'GBP', 'EGP', 'KWD', 'QAR', 'BHD', 'OMR'];

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _state = AppState.instance;
  bool _avatarBusy = false;

  Future<void> _changeAvatar() async {
    final p = _state.profile;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery')),
          if (p?.avatarUrl != null)
            ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(ctx, 'remove')),
        ]),
      ),
    );
    if (action == null) return;
    try {
      if (action == 'remove') {
        setState(() => _avatarBusy = true);
        _state.setProfile(await ExpenseApi.removeAvatar());
        return;
      }
      final file = await ImagePicker().pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null) return;
      setState(() => _avatarBusy = true);
      final bytes = await file.readAsBytes();
      _state.setProfile(await ExpenseApi.uploadAvatar(bytes, file.name));
      if (mounted) showMessage(context, 'Profile photo updated.');
    } on PlatformException catch (e) {
      if (mounted) showMessage(context, 'Could not open the photo picker: ${e.message ?? e.code}', error: true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _changeCurrency() async {
    final current = _state.currency;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Currency'),
        children: [
          for (final c in currencies)
            ListTile(
              title: Text(c),
              trailing: c == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, c),
            ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    try {
      _state.setProfile(await ExpenseApi.updateProfile(currency: picked));
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _changeTheme() async {
    final current = ThemeController.instance.value;
    final picked = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          for (final (mode, label) in [
            (ThemeMode.system, 'System default'),
            (ThemeMode.light, 'Light'),
            (ThemeMode.dark, 'Dark'),
          ])
            ListTile(
              title: Text(label),
              trailing: mode == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, mode),
            ),
        ],
      ),
    );
    if (picked != null) await ThemeController.instance.set(picked);
    if (mounted) setState(() {});
  }

  Future<void> _resetData() async {
    final ok = await confirm(context,
        title: 'Reset all data?',
        message: 'This deletes ALL your transactions, receipts, budgets and custom categories, '
            'and restores the default categories. This cannot be undone.',
        action: 'Reset');
    if (!ok) return;
    try {
      await ExpenseApi.resetData();
      await _state.reloadCategories();
      _state.dataChanged();
      if (mounted) showMessage(context, 'All data was reset.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _deleteAccount() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Delete account?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Your account and all your data will be permanently deleted. '
                'Type DELETE to confirm.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: (_) => setLocal(() {}),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: controller.text.trim() == 'DELETE' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Delete forever'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (ok != true) return;
    try {
      await ExpenseApi.deleteAccount();
      await AuthService.logout();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _logout() async {
    final ok = await confirm(context, title: 'Log out?', message: 'You can log in again any time.',
        action: 'Log out', danger: false);
    if (ok) await AuthService.logout();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_state, ThemeController.instance]),
      builder: (context, _) {
        final p = _state.profile;
        final provider = p?.provider ?? AuthService.currentUser?.appMetadata['provider'] as String?;
        final hasPassword = provider == 'email' || provider == 'phone';
        final themeLabel = switch (ThemeController.instance.value) {
          ThemeMode.light => 'Light',
          ThemeMode.dark => 'Dark',
          ThemeMode.system => 'System default',
        };
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(children: [
            const SizedBox(height: 8),
            Center(
              child: Stack(children: [
                _avatarBusy
                    ? const SizedBox.square(
                        dimension: 88, child: Center(child: CircularProgressIndicator()))
                    : UserAvatar(name: p?.displayName ?? '?', imageUrl: p?.avatarUrl, radius: 44),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IconButton.filledTonal(
                    tooltip: 'Change photo',
                    iconSize: 18,
                    icon: const Icon(Icons.edit),
                    onPressed: _avatarBusy ? null : _changeAvatar,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Text(p?.displayName ?? '',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            Text(p?.email ?? p?.phone ?? '',
                textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 8),
            _header('Account'),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Edit profile'),
              subtitle: Text([p?.country, p?.gender].whereType<String>().join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfilePage())),
            ),
            if (hasPassword)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Change password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDialog(context: context, builder: (_) => const _ChangePasswordDialog()),
              ),
            _header('Preferences'),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Currency'),
              subtitle: Text(_state.currency),
              onTap: _changeCurrency,
            ),
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('Theme'),
              subtitle: Text(themeLabel),
              onTap: _changeTheme,
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Categories'),
              subtitle: Text('${_state.categories.length} categories'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesPage())),
            ),
            _header('Data'),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Reset all data'),
              subtitle: const Text('Delete transactions, budgets and categories'),
              onTap: _resetData,
            ),
            if (_state.canDeleteAccount)
              ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
                title: Text('Delete account', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: _deleteAccount,
              ),
            _header('About'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('PennyWise'),
              subtitle: Text('Version 1.0.0 · Server: ${ApiConfig.baseUrl}'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text('Log out'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

}

// --------------------------------------------------------------- profile

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _form = GlobalKey<FormState>();
  final Profile? _p = AppState.instance.profile;
  late final _name = TextEditingController(text: _p?.fullName ?? '');
  late String? _country = countries.contains(_p?.country) ? _p?.country : null;
  late String? _gender = _p?.gender;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final updated = await ExpenseApi.updateProfile(
        fullName: _name.text.trim(),
        country: _country,
        gender: _gender,
      );
      AppState.instance.setProfile(updated);
      if (!mounted) return;
      showMessage(context, 'Profile updated.');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Full name', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
            validator: (v) => AuthValidators.fullName(v ?? ''),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _country,
            decoration: const InputDecoration(
                labelText: 'Country', prefixIcon: Icon(Icons.public), border: OutlineInputBorder()),
            items: [for (final c in countries) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _country = v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            decoration: const InputDecoration(
                labelText: 'Gender', prefixIcon: Icon(Icons.wc), border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Female', child: Text('Female')),
            ],
            onChanged: (v) => setState(() => _gender = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ]),
      ),
    );
  }
}

// -------------------------------------------------------------- password

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final err = AuthValidators.password(_password.text);
    if (err != null) return setState(() => _error = err);
    if (_password.text != _confirm.text) return setState(() => _error = 'Passwords do not match.');
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await AuthService.updatePassword(_password.text);
    if (!mounted) return;
    if (res.success) {
      Navigator.pop(context);
      showMessage(context, 'Password changed.');
    } else {
      setState(() {
        _saving = false;
        _error = res.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _password,
          obscureText: !_show,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'New password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          obscureText: !_show,
          decoration: InputDecoration(
            labelText: 'Confirm password',
            border: const OutlineInputBorder(),
            errorText: _error,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Text('At least 8 characters, with upper-case, lower-case and a number.',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
