import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuranNavigationState {
  final bool isReaderOpen;
  final int currentPage;

  const QuranNavigationState({this.isReaderOpen = false, this.currentPage = 1});

  QuranNavigationState copyWith({bool? isReaderOpen, int? currentPage}) {
    return QuranNavigationState(
      isReaderOpen: isReaderOpen ?? this.isReaderOpen,
      currentPage: currentPage ?? this.currentPage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuranNavigationState &&
          runtimeType == other.runtimeType &&
          isReaderOpen == other.isReaderOpen &&
          currentPage == other.currentPage;

  @override
  int get hashCode => isReaderOpen.hashCode ^ currentPage.hashCode;
}

class QuranNavigationNotifier extends StateNotifier<QuranNavigationState> {
  QuranNavigationNotifier() : super(const QuranNavigationState());

  void openReader(int page) {
    state = QuranNavigationState(
      isReaderOpen: true,
      currentPage: page.clamp(1, 604),
    );
  }

  void closeReader() {
    state = state.copyWith(isReaderOpen: false);
  }

  void setPage(int page) {
    state = state.copyWith(currentPage: page.clamp(1, 604));
  }
}

final quranNavigationProvider =
    StateNotifierProvider<QuranNavigationNotifier, QuranNavigationState>((ref) {
      return QuranNavigationNotifier();
    });
