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
