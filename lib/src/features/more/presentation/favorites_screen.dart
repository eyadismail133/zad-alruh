import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../progress/presentation/controllers/progress_controller.dart';
import '../../quran/presentation/quran_reader_screen.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  Future<void> _deleteBookmark(
    BuildContext context,
    WidgetRef ref,
    int id,
  ) async {
    try {
      await ref.read(bookmarksControllerProvider.notifier).deleteBookmark(id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: const Text('تعذر حذف العلامة.'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () => _deleteBookmark(context, ref, id),
            ),
          ),
        );
      }
    }
  }

  Future<void> _removeFavorite(
    BuildContext context,
    WidgetRef ref,
    String kind,
    String stableId,
  ) async {
    try {
      await ref
          .read(favoritesControllerProvider.notifier)
          .removeFavorite(kind, stableId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: const Text('تعذر إزالة العنصر من المفضلة.'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () => _removeFavorite(context, ref, kind, stableId),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(bookmarksControllerProvider);
    final favoritesAsync = ref.watch(favoritesControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المفضلة والعلامات'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'العلامات المرجعية'),
              Tab(text: 'المفضلة'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              // Bookmarks Tab
              bookmarksAsync.when(
                data: (bookmarks) {
                  if (bookmarks.isEmpty) {
                    return Center(
                      child: Text(
                        'لا توجد علامات مرجعية محفوظة بعد.',
                        style: TextStyle(
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: bookmarks.length,
                    itemBuilder: (ctx, index) {
                      final b = bookmarks[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(
                            Icons.bookmark,
                            color: AppColors.goldAccent,
                          ),
                          title: Text(
                            b.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            'صفحة ${b.pageNumber} من ٦٠٤',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: b.id != null
                                ? () => _deleteBookmark(context, ref, b.id!)
                                : null,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => QuranReaderScreen(
                                  initialPage: b.pageNumber,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => RetryableErrorView(
                  message: 'تعذر تحميل العلامات المرجعية.',
                  onRetry: () =>
                      ref.read(bookmarksControllerProvider.notifier).retry(),
                ),
              ),

              // Favorites Tab
              favoritesAsync.when(
                data: (favorites) {
                  if (favorites.isEmpty) {
                    return Center(
                      child: Text(
                        'لا توجد عناصر مفضلة محفوظة بعد.',
                        style: TextStyle(
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: favorites.length,
                    itemBuilder: (ctx, index) {
                      final fav = favorites[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(
                            Icons.favorite,
                            color: Colors.redAccent,
                          ),
                          title: Text(
                            fav.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            fav.subtitle ?? 'النوع: ${fav.contentKind}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _removeFavorite(
                              context,
                              ref,
                              fav.contentKind,
                              fav.stableId,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => RetryableErrorView(
                  message: 'تعذر تحميل العناصر المفضلة.',
                  onRetry: () =>
                      ref.read(favoritesControllerProvider.notifier).retry(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
