import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/core/theme/app_theme.dart';
import 'src/core/widgets/retryable_error_view.dart';
import 'src/features/progress/presentation/controllers/progress_controller.dart';
import 'src/features/shell/presentation/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ensureTimeZonesInitialized();
  runApp(
    const ProviderScope(
      child: ZadAlruhApp(),
    ),
  );
}

class ZadAlruhApp extends ConsumerWidget {
  const ZadAlruhApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(preferencesControllerProvider);

    final currentPrefs = prefsAsync.valueOrNull;
    final themeMode = currentPrefs?.darkMode == 'dark'
        ? ThemeMode.dark
        : currentPrefs?.darkMode == 'light'
            ? ThemeMode.light
            : ThemeMode.system;

    final userTextScale = currentPrefs?.textScale ?? 1.0;

    return MaterialApp(
      title: 'زادُ الروح',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      builder: (context, child) {
        // Respect system accessibility scaling, combining saved preference with system scale
        final systemScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
        final combinedScaler = TextScaler.linear(systemScaleFactor * userTextScale);

        return Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: combinedScaler,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: prefsAsync.when(
        data: (_) => const AppShell(),
        loading: () => prefsAsync.hasValue
            ? const AppShell()
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (err, _) => prefsAsync.hasValue
            ? const AppShell()
            : Scaffold(
                body: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: RetryableErrorView(
                        message: 'تعذر قراءة قاعدة البيانات المحلية أو إعدادات التطبيق: $err',
                        onRetry: () => ref.read(preferencesControllerProvider.notifier).retry(),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
