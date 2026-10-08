import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../dhikr/presentation/dhikr_screen.dart';
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
      ref.read(adhanAudioControllerProvider.notifier).stop().catchError((_) {});
    } else if (state == AppLifecycleState.resumed) {
      ref
          .read(prayerNotificationCoordinatorProvider)
          .reconcile(passive: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onSelectTab(int index) {
    if (_currentIndex != index) {
      ref.read(adhanAudioControllerProvider.notifier).stop().catchError((_) {});
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
      const DhikrScreen(),
      const MoreScreen(),
    ];

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: IndexedStack(
            index: _currentIndex,
            children: pages,
          ),
        ),
      ),
      bottomNavigationBar: Center(
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onSelectTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'الرئيسية',
              ),
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book),
                label: 'القرآن',
              ),
              NavigationDestination(
                icon: Icon(Icons.access_time_filled_outlined),
                selectedIcon: Icon(Icons.access_time_filled),
                label: 'الصلاة',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: 'الأذكار',
              ),
              NavigationDestination(
                icon: Icon(Icons.more_horiz_outlined),
                selectedIcon: Icon(Icons.more_horiz),
                label: 'المزيد',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
