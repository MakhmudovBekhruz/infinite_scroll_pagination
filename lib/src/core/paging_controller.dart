import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:infinite_scroll_pagination/src/core/paging_state.dart';

/// A callback to get the next page key.
/// If this function returns `null`, it indicates that there are no more pages to load.
typedef NextPageKeyCallback<PageKeyType, ItemType> = PageKeyType? Function(
    PagingState<PageKeyType, ItemType> state);

/// A callback to fetch a page.
typedef FetchPageCallback<PageKeyType, ItemType> = FutureOr<List<ItemType>>
    Function(PageKeyType pageKey);

/// A controller to handle a [PagingState].
///
/// This is an unopinionated controller implemented through vanilla Flutter's [ValueNotifier].
/// The controller acts as a mutex to prevent multiple fetches at the same time.
///
/// Note that for convenience, fetch operations are not atomic.
/// The state may be updated during a fetch operation. This should be done fully synchronously,
/// as otherwise, the state may become desynchronized.
///
/// Each item managed by the controller must have a unique string identifier resolved by
/// [getItemId]. The identifier is used to keep track of items and to support targeted updates.
class PagingController<PageKeyType, ItemType>
    extends ValueNotifier<PagingState<PageKeyType, ItemType>> {
  PagingController({
    PagingState<PageKeyType, ItemType>? value,
    required NextPageKeyCallback<PageKeyType, ItemType> getNextPageKey,
    required FetchPageCallback<PageKeyType, ItemType> fetchPage,
    required String Function(ItemType item) getItemId,
  })  : _getNextPageKey = getNextPageKey,
        _fetchPage = fetchPage,
        _getItemId = getItemId,
        super(
          value ?? PagingState<PageKeyType, ItemType>(),
        );

  /// The function to get the next page key.
  /// If this function returns `null`, it indicates that there are no more pages to load.
  final NextPageKeyCallback<PageKeyType, ItemType> _getNextPageKey;

  /// The function to fetch a page.
  final FetchPageCallback<PageKeyType, ItemType> _fetchPage;

  /// The function to resolve an item's unique identifier.
  final String Function(ItemType item) _getItemId;

  /// Keeps track of the current operation.
  /// If the operation changes during its execution, the operation is cancelled.
  ///
  /// Instead of using this property directly, use [fetchNextPage], [refresh], or [cancel].
  /// If you are extending this class, check and set this property before and after the fetch operation.
  @protected
  @visibleForTesting
  Object? operation;

  /// Fetches the next page.
  ///
  /// If called while a page is fetching or no more pages are available, this method does nothing.
  void fetchNextPage() async {
    // We are already loading a new page.
    if (this.operation != null) return;

    final operation = this.operation = Object();

    value = value.copyWith(
      isLoading: true,
      error: null,
    );

    // we use a local copy of value,
    // so that we only send one notification now and at the end of the method.
    PagingState<PageKeyType, ItemType> state = value;

    try {
      // There are no more pages to load.
      if (!state.hasNextPage) return;

      final nextPageKey = _getNextPageKey(state);

      // We are at the end of the list.
      if (nextPageKey == null) {
        state = state.copyWith(hasNextPage: false);
        return;
      }

      final fetchResult = _fetchPage(nextPageKey);
      List<ItemType> newItems;

      // If the result is synchronous, we can directly assign it in the same tick.
      if (fetchResult is Future) {
        newItems = await fetchResult;
      } else {
        newItems = fetchResult;
      }

      final newItemIds = newItems.map(_getItemId).toList(growable: false);

      // Update our state in case it was modified during the fetch operation.
      // This beaks atomicity, but is necessary to allow users to modify the state during a fetch.
      state = value;

      _validateNewIds(newItemIds, state.itemIds);

      state = state.copyWith(
        pages: [...?state.pages, newItems],
        itemIds: [...?state.itemIds, newItemIds],
        keys: [...?state.keys, nextPageKey],
      );
    } catch (error) {
      state = state.copyWith(error: error);

      if (error is! Exception) {
        // Errors which are not exceptions indicate that something
        // went unexpectedly wrong. These errors are rethrown
        // so they can be logged and investigated.
        rethrow;
      }
    } finally {
      if (operation == this.operation) {
        value = state.copyWith(isLoading: false);
        this.operation = null;
      }
    }
  }

  /// Restarts the pagination process.
  ///
  /// This cancels the current fetch operation and resets the state.
  void refresh() {
    operation = null;
    value = value.reset();
  }

  /// Cancels the current fetch operation.
  ///
  /// This can be called right before a call to [fetchNextPage] to force a new fetch.
  void cancel() {
    operation = null;
    value = value.copyWith(isLoading: false);
  }

  /// Inserts a new item into the flattened items list at [index].
  ///
  /// The provided [id] must be unique across all items currently managed by the controller.
  /// Throws a [StateError] if the id already exists or a [RangeError] if [index]
  /// is outside the valid range.
  void insertItem({
    required String id,
    required ItemType item,
    required int index,
  }) {
    final state = value;

    final pages = state.pages?.map((page) => page.toList()).toList() ?? [];
    final itemIdsPages =
        state.itemIds?.map((page) => page.toList()).toList() ?? [];

    while (itemIdsPages.length < pages.length) {
      final pageIndex = itemIdsPages.length;
      itemIdsPages.add(
        pages[pageIndex].map(_getItemId).toList(),
      );
    }

    final existingIds = itemIdsPages.expand((ids) => ids).toSet();
    if (!existingIds.add(id)) {
      throw StateError('Item id "$id" already exists.');
    }

    final totalItems = pages.fold<int>(0, (count, page) => count + page.length);
    if (index < 0 || index > totalItems) {
      throw RangeError.range(index, 0, totalItems);
    }

    if (pages.isEmpty) {
      pages.add([item]);
      itemIdsPages.add([id]);
    } else {
      var offset = 0;
      var inserted = false;
      for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
        final page = pages[pageIndex];
        final ids = itemIdsPages[pageIndex];

        if (index <= offset + page.length) {
          final pageOffset = index - offset;
          page.insert(pageOffset, item);
          ids.insert(pageOffset, id);
          inserted = true;
          break;
        }
        offset += page.length;
      }

      if (!inserted) {
        pages.last.add(item);
        itemIdsPages.last.add(id);
      }
    }

    value = state.copyWith(
      pages: pages,
      itemIds: itemIdsPages,
    );
  }

  void _validateNewIds(
    List<String> newIds,
    List<List<String>>? existingIds,
  ) {
    final existing = existingIds == null
        ? <String>{}
        : existingIds.expand((ids) => ids).toSet();

    final seen = <String>{};
    for (final id in newIds) {
      if (!seen.add(id)) {
        throw StateError('Duplicate id "$id" detected in the same page.');
      }
      if (!existing.add(id)) {
        throw StateError('Duplicate id "$id" detected across pages.');
      }
    }
  }

  @override
  void dispose() {
    operation = null;
    super.dispose();
  }
}
