import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';

class ThemeCubit extends Cubit<ThemeMode> {
  final StorageService _storageService;
  static const String _themeKey = 'user_theme_mode';

  ThemeCubit({required StorageService storageService})
      : _storageService = storageService,
        super(ThemeMode.system) {
    loadTheme();
  }

  Future<void> loadTheme() async {
    final result = await _storageService.getString(_themeKey);
    result.fold(
      (failure) => emit(ThemeMode.system),
      (themeStr) {
        if (themeStr == 'light') {
          emit(ThemeMode.light);
        } else if (themeStr == 'dark') {
          emit(ThemeMode.dark);
        } else {
          emit(ThemeMode.system);
        }
      },
    );
  }

  Future<void> setTheme(ThemeMode mode) async {
    emit(mode);
    String themeStr = 'system';
    if (mode == ThemeMode.light) {
      themeStr = 'light';
    } else if (mode == ThemeMode.dark) {
      themeStr = 'dark';
    }
    await _storageService.saveString(_themeKey, themeStr);
  }
}
