import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../dhikr/presentation/adhkar_hub_screen.dart';
import '../../home/presentation/home_screen.dart';
import '../../more/presentation/more_screen.dart';
import '../../prayer/domain/services/prayer_notification_coordinator.dart';
import '../../prayers/presentation/controllers/adhan_audio_controller.dart';
import '../../prayers/presentation/prayers_screen.dart';
import '../../quran/presentation/quran_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(prayerNotificationCoordinatorProvider)
            .reconcile(passive: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _stopAdhanPreview();
    } else if (state == AppLifecycleState.resumed) {
      ref.read(prayerNotificationCoordinatorProvider).reconcile(passive: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Adhan previews stop when leaving the screen; Quran recitation keeps
  /// playing across tabs and while the app is in the background.
  void _stopAdhanPreview() {
    final audio = ref.read(adhanAudioControllerProvider);
    if (audio.sourceType == AudioPlaybackSource.quran) return;
    ref.read(adhanAudioControllerProvider.notifier).stop().catchError((_) {});
  }

  void _onSelectTab(int index) {
    if (_currentIndex != index) {
      _stopAdhanPreview();
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomeScreen(onNavigateTab: _onSelectTab),
      const QuranScreen(),
      const PrayersScreen(),
      const AdhkarHubScreen(),
      const MoreScreen(),
    ];
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: IndexedStack(index: _currentIndex, children: pages),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: _onSelectTab,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'الرئيسية',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    selectedIcon: Icon(Icons.menu_book_rounded),
                    label: 'القرآن',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.mosque_outlined),
                    selectedIcon: Icon(Icons.mosque_rounded),
                    label: 'الصلاة',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome_outlined),
                    selectedIcon: Icon(Icons.auto_awesome),
                    label: 'الأذكار',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: 'المزيد',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
