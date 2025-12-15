import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_scroll_pagination/src/core/paging_state.dart';
import 'package:infinite_scroll_pagination/src/core/paging_status.dart';

void main() {
  group('PagingStatusExtension', () {
    late PagingState<int, String> pagingState;

    test(
        'returns loadingFirstPage status when actively loading first page with no items and no error',
        () {
      pagingState = PagingState<int, String>(isLoading: true);
      expect(pagingState.status, PagingStatus.loadingFirstPage);
    });

    test(
        'returns loadingFirstPage status for initial state (before loading starts)',
        () {
      pagingState = PagingState<int, String>(isLoading: false);
      expect(pagingState.status, PagingStatus.loadingFirstPage);
    });

    test(
        'returns firstPageError status when first page has no items and there is an error',
        () {
      pagingState = PagingState<int, String>(error: Exception('Error'));
      expect(pagingState.status, PagingStatus.firstPageError);
    });

    test('returns noItemsFound status when there are no items and no error',
        () {
      pagingState = PagingState<int, String>(
        pages: const [],
        itemIds: const [],
        keys: const [],
        hasNextPage: false,
      );
      expect(pagingState.status, PagingStatus.noItemsFound);
    });

    test(
        'returns ongoing status when items exist, there is no error, and more pages are available',
        () {
      pagingState = PagingState<int, String>(
        pages: const [
          ['Item 1']
        ],
        itemIds: const [
          ['Item 1']
        ],
        keys: const [1],
        hasNextPage: true,
      );
      expect(pagingState.status, PagingStatus.ongoing);
    });

    test(
        'returns subsequentPageError status when items exist and there is an error',
        () {
      pagingState = PagingState<int, String>(
        pages: const [
          ['Item 1']
        ],
        itemIds: const [
          ['Item 1']
        ],
        keys: const [1],
        error: Exception('Error'),
        hasNextPage: true,
      );
      expect(pagingState.status, PagingStatus.subsequentPageError);
    });

    test(
        'returns completed status when items exist and no more pages are available',
        () {
      pagingState = PagingState<int, String>(
        pages: const [
          ['Item 1']
        ],
        itemIds: const [
          ['Item 1']
        ],
        keys: const [1],
        hasNextPage: false,
      );
      expect(pagingState.status, PagingStatus.completed);
    });

    test(
        'returns ongoing status during silent refresh with existing items',
        () {
      pagingState = PagingState<int, String>(
        pages: const [
          ['Item 1']
        ],
        itemIds: const [
          ['Item 1']
        ],
        keys: const [1],
        isSilentRefresh: true,
        hasNextPage: true,
      );
      expect(pagingState.status, PagingStatus.ongoing);
    });

    test(
        'does not return loadingFirstPage status during silent refresh',
        () {
      pagingState = PagingState<int, String>(
        isSilentRefresh: true,
      );
      // During silent refresh, even with no items, it should not be loadingFirstPage
      expect(pagingState.status, isNot(PagingStatus.loadingFirstPage));
    });
  });
}
