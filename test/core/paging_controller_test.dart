import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

void main() {
  group('PagingController', () {
    late PagingController<int, String> pagingController;
    late int? nextPageKey;
    late bool fetchCalled;
    late List<String> fetchedItems;

    setUp(() {
      nextPageKey = 1;
      fetchCalled = false;
      fetchedItems = ['Item 1', 'Item 2'];

      getNextPageKey(state) => nextPageKey;
      List<String> fetchPage(int pageKey) {
        fetchCalled = true;
        return fetchedItems;
      }

      pagingController = PagingController<int, String>(
        getNextPageKey: getNextPageKey,
        fetchPage: fetchPage,
        getItemId: (item) => item,
      );
    });

    group('fetchNextPage', () {
      test('requests the next page', () async {
        pagingController.fetchNextPage();

        expect(fetchCalled, isTrue);
        expect(pagingController.value.pages, [fetchedItems]);
        expect(pagingController.value.itemIds, [fetchedItems]);
        expect(pagingController.value.keys, [nextPageKey]);
      });

      test('fetches a page synchronously when possible', () async {
        pagingController.fetchNextPage();

        await Future.value(null);

        expect(fetchCalled, isTrue);
        expect(pagingController.value.pages, [fetchedItems]);
        expect(pagingController.value.itemIds, [fetchedItems]);
        expect(pagingController.value.keys, [nextPageKey]);
      });

      test('only runs one fetch at a given time', () async {
        final completer = Completer<List<String>>();

        pagingController = PagingController<int, String>(
          getNextPageKey: (state) => nextPageKey,
          fetchPage: (_) => completer.future,
          getItemId: (item) => item,
        );

        pagingController.fetchNextPage();
        pagingController.fetchNextPage();

        await Future.value(null);

        expect(fetchCalled, isFalse);
        expect(pagingController.value.isLoading, isTrue);

        completer.complete(fetchedItems);
        await Future.delayed(Duration.zero);

        expect(pagingController.value.isLoading, isFalse);
      });

      test('stops if next page key is null', () async {
        nextPageKey = null;
        pagingController.fetchNextPage();

        await Future.value(null);

        expect(fetchCalled, isFalse);
        expect(pagingController.value.hasNextPage, isFalse);
      });

      test('stops if no more pages are available', () async {
        pagingController.value =
            pagingController.value.copyWith(hasNextPage: false);
        pagingController.fetchNextPage();
        expect(fetchCalled, isFalse);
      });

      // We have intentionally broken atomicity of PagingController.
      // This is because we want users to be able to modify their item list even during a fetch.
      // It is unclear whether this will come back to bite us.
      test('allows modifying state during a fetch', () async {
        pagingController = PagingController<int, String>(
          getNextPageKey: (state) => (state.keys?.last ?? 0) + 1,
          fetchPage: (page) => Future.value(['Item $page']),
          getItemId: (item) => item,
        );

        pagingController.fetchNextPage();

        await Future.value(null);

        pagingController.fetchNextPage();

        pagingController.value = pagingController.value.copyWith(
          pages: pagingController.value.pages
              ?.map(
                (a) => a.map((b) => b.toUpperCase()).toList(),
              )
              .toList(),
        );

        await Future.value(null);

        expect(pagingController.value.isLoading, isFalse);
        expect(pagingController.value.pages, [
          ['ITEM 1'],
          ['Item 2'],
        ]);
      });

      test('catches Exceptions', () async {
        pagingController = PagingController<int, String>(
          getNextPageKey: (state) => nextPageKey,
          fetchPage: (_) => throw Exception(),
          getItemId: (item) => item,
        );

        pagingController.fetchNextPage();

        expect(pagingController.value.isLoading, isFalse);
        expect(pagingController.value.error, isA<Exception>());
      });

      test('rethrows Errors', () async {
        pagingController = PagingController<int, String>(
          getNextPageKey: (state) => nextPageKey,
          fetchPage: (_) => throw Error(),
          getItemId: (item) => item,
        );

        expect(() async => pagingController.fetchNextPage(),
            throwsA(isA<Error>()));

        expect(pagingController.value.isLoading, isFalse);
        expect(pagingController.value.error, isA<Error>());
      });

      test('throws when duplicate ids are returned', () async {
        pagingController = PagingController<int, String>(
          getNextPageKey: (state) => state.keys?.last == null ? 1 : null,
          fetchPage: (_) => ['Dup', 'Dup'],
          getItemId: (item) => item,
        );

        expect(
          () => pagingController.fetchNextPage(),
          throwsStateError,
        );
      });
    });

    group('refresh', () {
      test('resets state', () async {
        pagingController.value = PagingState<int, String>(
          pages: const [
            ['Item 1']
          ],
          itemIds: const [
            ['Item 1']
          ],
          keys: const [1],
        );

        pagingController.refresh();

        expect(pagingController.value.pages, isNull);
        expect(pagingController.value.itemIds, isNull);
        expect(pagingController.value.keys, isNull);
        expect(pagingController.value.isLoading, isFalse);
        expect(pagingController.value.error, isNull);
      });

      test('resets state with withLoaderUI: true', () async {
        pagingController.value = PagingState<int, String>(
          pages: const [
            ['Item 1']
          ],
          itemIds: const [
            ['Item 1']
          ],
          keys: const [1],
        );

        pagingController.refresh(withLoaderUI: true);

        expect(pagingController.value.pages, isNull);
        expect(pagingController.value.itemIds, isNull);
        expect(pagingController.value.keys, isNull);
        expect(pagingController.value.isLoading, isFalse);
        expect(pagingController.value.error, isNull);
        expect(pagingController.value.isSilentRefresh, isFalse);
      });

      test('preserves data with withLoaderUI: false', () async {
        final initialPages = const [
          ['Item 1', 'Item 2']
        ];
        final initialItemIds = const [
          ['Item 1', 'Item 2']
        ];
        final initialKeys = const [1];

        pagingController.value = PagingState<int, String>(
          pages: initialPages,
          itemIds: initialItemIds,
          keys: initialKeys,
        );

        pagingController.refresh(withLoaderUI: false);

        expect(pagingController.value.pages, initialPages);
        expect(pagingController.value.itemIds, initialItemIds);
        expect(pagingController.value.keys, initialKeys);
        expect(pagingController.value.isLoading, isFalse);
        expect(pagingController.value.error, isNull);
        expect(pagingController.value.isSilentRefresh, isTrue);
      });

      test('replaces data after silent refresh completes', () async {
        final oldItems = ['Old Item 1', 'Old Item 2'];
        final newItems = ['New Item 1', 'New Item 2'];

        pagingController.value = PagingState<int, String>(
          pages: [oldItems],
          itemIds: [oldItems],
          keys: const [1],
        );

        // Override fetchedItems for this test
        fetchedItems = newItems;

        pagingController.refresh(withLoaderUI: false);

        expect(pagingController.value.pages, [oldItems]);
        expect(pagingController.value.isSilentRefresh, isTrue);

        pagingController.fetchNextPage();

        await Future.value(null);

        expect(pagingController.value.pages, [newItems]);
        expect(pagingController.value.itemIds, [newItems]);
        expect(pagingController.value.keys, [1]);
        expect(pagingController.value.isSilentRefresh, isFalse);
        expect(pagingController.value.isLoading, isFalse);
      });

      test('sets hasNextPage to true during silent refresh', () async {
        // Setup: Create a state where hasNextPage is false
        pagingController.value = PagingState<int, String>(
          pages: const [
            ['Item 1', 'Item 2']
          ],
          itemIds: const [
            ['Item 1', 'Item 2']
          ],
          keys: const [1],
          hasNextPage: false, // Explicitly set to false
        );

        // Act: Call refresh with withLoaderUI: false
        pagingController.refresh(withLoaderUI: false);

        // Assert: hasNextPage should be set to true immediately
        expect(pagingController.value.hasNextPage, isTrue,
            reason: 'hasNextPage should be true after calling refresh(withLoaderUI: false)');
        expect(pagingController.value.isSilentRefresh, isTrue);
      });

      test('triggers fetchPage during silent refresh even when hasNextPage is false', () async {
        // Setup: Create a state where hasNextPage is false
        pagingController.value = PagingState<int, String>(
          pages: const [
            ['Item 1', 'Item 2']
          ],
          itemIds: const [
            ['Item 1', 'Item 2']
          ],
          keys: const [1],
          hasNextPage: false, // Explicitly set to false
        );

        // Reset fetchCalled to track if fetchPage is called
        fetchCalled = false;
        final newItems = ['New Item 1', 'New Item 2'];
        fetchedItems = newItems;

        // Act: Call refresh with withLoaderUI: false
        pagingController.refresh(withLoaderUI: false);

        // Wait for async operations
        await Future.value(null);

        // Assert: fetchPage should have been called
        expect(fetchCalled, isTrue, reason: 'fetchPage should be called during silent refresh even when hasNextPage was false');
        
        // Assert: The state should be updated correctly
        expect(pagingController.value.pages, [newItems]);
        expect(pagingController.value.itemIds, [newItems]);
        expect(pagingController.value.isSilentRefresh, isFalse);
        expect(pagingController.value.isLoading, isFalse);
      });

      test('silent refresh restarts from page 1 instead of continuing from last page', () async {
        // This test validates the fix for the issue where refresh(withLoaderUI: false)
        // would continue from the last page instead of restarting from page 1.
        
        int? requestedPageKey;
        
        // Setup a controller that tracks which page was requested
        pagingController = PagingController<int, String>(
          getNextPageKey: (state) {
            // Typical pagination logic pattern used in tests:
            // if no keys, start at 1; otherwise, next page.
            if (state.keys == null || state.keys!.isEmpty) {
              return 1;
            }
            return state.keys!.last + 1;
          },
          fetchPage: (pageKey) {
            requestedPageKey = pageKey;
            return ['Item ${pageKey}A', 'Item ${pageKey}B'];
          },
          getItemId: (item) => item,
        );

        // Load pages 1, 2, 3
        pagingController.fetchNextPage();
        await Future.value(null);
        expect(requestedPageKey, 1);

        pagingController.fetchNextPage();
        await Future.value(null);
        expect(requestedPageKey, 2);

        pagingController.fetchNextPage();
        await Future.value(null);
        expect(requestedPageKey, 3);

        // Verify we have 3 pages loaded
        expect(pagingController.value.pages?.length, 3);
        expect(pagingController.value.keys, [1, 2, 3]);

        // Now call silent refresh
        pagingController.refresh(withLoaderUI: false);

        // Wait for the refresh to complete
        await Future.value(null);

        // The fix ensures that page 1 is fetched (not page 4)
        expect(requestedPageKey, 1, 
            reason: 'Silent refresh should fetch page 1, not continue from page 4');

        // After silent refresh, we should have only 1 page (the new page 1)
        expect(pagingController.value.pages?.length, 1);
        expect(pagingController.value.keys, [1]);
        expect(pagingController.value.pages?[0], ['Item 1A', 'Item 1B']);
      });

      test('silent refresh works with nextIntPageKey extension', () async {
        // This test validates the fix works with the convenience extension.
        
        int? requestedPageKey;
        
        // Setup a controller using the nextIntPageKey extension
        pagingController = PagingController<int, String>(
          getNextPageKey: (state) => state.lastPageIsEmpty ? null : state.nextIntPageKey,
          fetchPage: (pageKey) {
            requestedPageKey = pageKey;
            return pageKey > 2 ? [] : ['Item ${pageKey}A', 'Item ${pageKey}B'];
          },
          getItemId: (item) => item,
        );

        // Load pages 1, 2 (page 3 would be empty)
        pagingController.fetchNextPage();
        await Future.value(null);
        expect(requestedPageKey, 1);

        pagingController.fetchNextPage();
        await Future.value(null);
        expect(requestedPageKey, 2);

        // Verify we have 2 pages loaded
        expect(pagingController.value.pages?.length, 2);
        expect(pagingController.value.keys, [1, 2]);

        // Now call silent refresh
        pagingController.refresh(withLoaderUI: false);

        // Wait for the refresh to complete
        await Future.value(null);

        // With the fix, nextIntPageKey on empty state returns (0) + 1 = 1
        expect(requestedPageKey, 1, 
            reason: 'Silent refresh with nextIntPageKey should fetch page 1');

        // After silent refresh, we should have only 1 page (the new page 1)
        expect(pagingController.value.pages?.length, 1);
        expect(pagingController.value.keys, [1]);
      });

      test('cancels previous refresh', () async {
        bool hasBeenCalled = false;
        bool hasFailed = false;

        final completer1 = Completer<List<String>>();
        final completer2 = Completer<List<String>>();

        pagingController = PagingController<int, String>(
            getNextPageKey: (state) => nextPageKey,
            fetchPage: (_) {
              if (hasBeenCalled) {
                return completer2.future;
              } else {
                hasBeenCalled = true;
                return completer1.future;
              }
            },
            getItemId: (item) => item);

        final wrongItems = ['Wrong Item 1', 'Wrong Item 2'];

        pagingController.addListener(() {
          try {
            expect(pagingController.value.pages, isNot([wrongItems]));
          } catch (e) {
            hasFailed = true;
          }
        });

        pagingController.fetchNextPage();

        await Future.value(null);

        pagingController.refresh();
        pagingController.fetchNextPage();

        await Future.value(null);

        completer1.complete(wrongItems);
        completer2.complete(fetchedItems);

        await Future.value(null);

        expect(pagingController.value.isLoading, isFalse);
        expect(pagingController.value.pages, [fetchedItems]);
        expect(pagingController.value.itemIds, [fetchedItems]);
        expect(hasFailed, isFalse);
      });
    });

    group('cancel', () {
      test('resets state and stops fetch', () async {
        pagingController = PagingController<int, String>(
          getNextPageKey: (state) => (state.keys?.last ?? 0) + 1,
          fetchPage: (page) => Future.value(['Item $page']),
          getItemId: (item) => item,
        );

        pagingController.fetchNextPage();

        await Future.value(null);

        expect(pagingController.value.pages, [
          ['Item 1']
        ]);
        expect(pagingController.value.itemIds, [
          ['Item 1']
        ]);

        pagingController.fetchNextPage();

        pagingController.cancel();

        await Future.value(null);

        expect(pagingController.value.isLoading, isFalse);
        expect(pagingController.value.pages, [
          ['Item 1']
        ]);
        expect(pagingController.value.itemIds, [
          ['Item 1']
        ]);
      });
    });

    group('insertItem', () {
      test('inserts into empty state', () {
        pagingController.insertItem(
          id: 'new-id',
          item: 'New Item',
          index: 0,
        );

        expect(pagingController.value.pages, [
          ['New Item']
        ]);
        expect(pagingController.value.itemIds, [
          ['new-id']
        ]);
      });

      test('inserts at specific position', () {
        pagingController.value = PagingState<int, String>(
          pages: const [
            ['Item 1', 'Item 3']
          ],
          itemIds: const [
            ['id-1', 'id-3']
          ],
          keys: const [1],
        );

        pagingController.insertItem(
          id: 'id-2',
          item: 'Item 2',
          index: 1,
        );

        expect(pagingController.value.pages, [
          ['Item 1', 'Item 2', 'Item 3']
        ]);
        expect(pagingController.value.itemIds, [
          ['id-1', 'id-2', 'id-3']
        ]);
      });

      test('throws when id already exists', () {
        pagingController.value = PagingState<int, String>(
          pages: const [
            ['Item 1']
          ],
          itemIds: const [
            ['dup']
          ],
          keys: const [1],
        );

        expect(
          () => pagingController.insertItem(
            id: 'dup',
            item: 'Item 2',
            index: 1,
          ),
          throwsStateError,
        );
      });

      test('throws when index out of range', () {
        expect(
          () => pagingController.insertItem(
            id: 'out',
            item: 'Item',
            index: 1,
          ),
          throwsRangeError,
        );
      });
    });
  });
}
