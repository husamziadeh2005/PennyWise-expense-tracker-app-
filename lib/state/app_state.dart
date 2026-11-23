import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'package:expense_tracker/core/network/api_client.dart';
import 'package:expense_tracker/data/api/expense_api.dart';
import 'package:expense_tracker/data/models/models.dart';

/// App-wide state shared by all tabs (a plain ChangeNotifier, no package).
///
/// * [profile] and [categories] are loaded once after login.
/// * [dataVersion] goes up whenever transactions / budgets change, here or
///   on another device (Supabase Realtime). Pages listen to it and reload.
class AppState extends ChangeNotifier {
  AppState._();
  static final instance = AppState._();

  Profile? profile;
  List<Category> categories = const [];
  bool canDeleteAccount = false;
  bool loading = false;
  String? loadError;

  /// True when [loadError] means "the API server could not be reached"
  /// (not started, wrong API_URL, no Wi-Fi). We then retry automatically.
  bool loadErrorIsNetwork = false;
  int dataVersion = 0;

  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _retryTimer;
  bool _active = false;

  static const retryEvery = Duration(seconds: 3);

  String get currency => profile?.currency ?? 'USD';

  List<Category> categoriesOf(TxType type) => categories.where((c) => c.type == type).toList();

  Category? categoryById(String? id) => categories.where((c) => c.id == id).firstOrNull;

  /// Call after login (the main shell does this).
  /// [realtime] is only turned off in tests (no Supabase there).
  Future<void> start({bool realtime = true}) async {
    _active = true;
    await load();
    if (realtime) _listenRealtime();
  }

  /// Loads profile + categories. If the server is unreachable we keep the
  /// error on screen and quietly try again every [retryEvery], so the app
  /// recovers on its own as soon as the API is started.
  Future<void> load({bool quiet = false}) async {
    _retryTimer?.cancel();
    if (!quiet) {
      loading = true;
      loadError = null;
      notifyListeners();
    }
    try {
      final results = await Future.wait([ExpenseApi.me(), ExpenseApi.categories()]);
      final me = results[0] as ({Profile? profile, bool canDeleteAccount});
      profile = me.profile;
      canDeleteAccount = me.canDeleteAccount;
      categories = results[1] as List<Category>;
      loadError = null;
      loadErrorIsNetwork = false;
    } catch (e) {
      loadError = e.toString();
      loadErrorIsNetwork = e is ApiException && e.isNetwork;
      if (loadErrorIsNetwork && _active) {
        _retryTimer = Timer(retryEvery, () => load(quiet: true));
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> reloadCategories() async {
    categories = await ExpenseApi.categories();
    notifyListeners();
  }

  void setProfile(Profile p) {
    profile = p;
    notifyListeners();
  }

  /// Tell every page that data changed (after add / edit / delete).
  void dataChanged() {
    dataVersion++;
    notifyListeners();
  }

  /// Realtime: any change to this user's rows (e.g. from a second phone)
  /// refreshes the screens. RLS makes sure we only get our own changes.
  void _listenRealtime() {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null || _channel != null) return;
    final mine = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid);

    _channel = client.channel('pennywise-$uid')
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'transactions',
          filter: mine,
          callback: (_) => _scheduleRefresh())
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'budgets',
          filter: mine,
          callback: (_) => _scheduleRefresh())
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'categories',
          filter: mine,
          callback: (_) => _scheduleRefresh(categories: true))
      ..subscribe();
  }

  bool _refreshCategories = false;

  // Many events can arrive at once (e.g. "reset data"), so wait a moment
  // and refresh once.
  void _scheduleRefresh({bool categories = false}) {
    _refreshCategories |= categories;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (_refreshCategories) {
        _refreshCategories = false;
        await reloadCategories().catchError((_) {});
      }
      dataChanged();
    });
  }

  /// Call on logout so the next user starts clean.
  Future<void> stop() async {
    _active = false;
    _retryTimer?.cancel();
    _debounce?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) await Supabase.instance.client.removeChannel(channel);
    profile = null;
    categories = const [];
    canDeleteAccount = false;
    loadError = null;
    loadErrorIsNetwork = false;
    dataVersion = 0;
  }
}

/// Light / dark / system theme, remembered on the device.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.system);
  static final instance = ThemeController._();

  static const _key = 'theme_mode';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = ThemeMode.values.byName(prefs.getString(_key) ?? 'system');
    } catch (_) {/* keep default */}
  }

  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }
}
