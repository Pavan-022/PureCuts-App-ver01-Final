import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/services/firestore_service.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/core/widgets/product_card.dart';
import 'package:purecuts/core/widgets/shimmer_widgets.dart';
import 'package:purecuts/core/widgets/sticky_cart_bar.dart';
import 'package:purecuts/features/home/home_provider.dart';
import 'package:purecuts/features/support_chat/widgets/support_chat_fab.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class ProductListScreen extends StatefulWidget {
  final String? initialCategory;
  final String? initialBrand;
  final String? initialTag;
  final String? initialQuery;
  const ProductListScreen({
    super.key,
    this.initialCategory,
    this.initialBrand,
    this.initialTag,
    this.initialQuery,
  });

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  static const int _pageSize = 24;
  String _selectedCategory = 'All';
  String? _selectedBrand;
  String? _selectedTag;
  String _sort = 'popular';
  final _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechReady = false;
  bool _isListening = false;
  bool _speechDialogVisible = false;
  String? _speechLocaleId;
  ValueNotifier<String>? _activeTranscript;
  bool _pendingVoiceSearch = false;

  final List<Map<String, dynamic>> _pagedProducts = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastProductDoc;
  bool _hasMoreProducts = true;
  bool _isPageLoading = false;
  bool _isInitialLoading = false;
  bool _isSearchHydrating = false;
  String? _pagingError;

  String _searchQuery = '';

  String _scopeKey() {
    final category = _selectedCategory.trim().toLowerCase();
    final brand = (_selectedBrand ?? '').trim().toLowerCase();
    return '$category|$brand';
  }

  bool get _needsFullScopeForSearch {
    final hasQuery = _searchQuery.trim().isNotEmpty;
    final hasTagFilter = (_selectedTag ?? '').trim().isNotEmpty;
    return hasQuery || hasTagFilter;
  }

  Future<void> _hydrateScopeForSearchIfNeeded() async {
    if (!_needsFullScopeForSearch) return;
    if (_isInitialLoading || _isPageLoading || _isSearchHydrating) return;

    final initialScope = _scopeKey();
    setState(() {
      _isSearchHydrating = true;
      _pagingError = null;
    });

    try {
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      var hasMore = true;
      final fetched = <Map<String, dynamic>>[];
      var guard = 0;

      while (hasMore && guard < 200) {
        guard += 1;

        if (!mounted || _scopeKey() != initialScope) break;

        final page = await _firestoreService.getProductsPageFiltered(
          limit: 120,
          startAfterDoc: cursor,
          category: null,
          brand: (_selectedBrand ?? '').trim().isEmpty ? null : _selectedBrand,
        );

        fetched.addAll(page.products.map((p) => p.toProductMap()));
        cursor = page.lastDocument;
        hasMore = page.hasMore && cursor != null;

        if (!hasMore) break;
      }

      if (!mounted || _scopeKey() != initialScope) return;

      setState(() {
        final map = <String, Map<String, dynamic>>{};
        for (final p in _pagedProducts) {
          final id = (p['id'] ?? '').toString();
          if (id.isNotEmpty) map[id] = p;
        }
        for (final p in fetched) {
          final id = (p['id'] ?? '').toString();
          if (id.isNotEmpty) map[id] = p;
        }
        _pagedProducts
          ..clear()
          ..addAll(map.values);
        _lastProductDoc = cursor ?? _lastProductDoc;
        _hasMoreProducts = hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _pagingError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isSearchHydrating = false);
      }
    }
  }

  String _speechErrorMessage(dynamic error) {
    final rawMsg = (error?.errorMsg ?? error?.toString() ?? '').toString();
    final msg = rawMsg.toLowerCase();
    if (msg.contains('no_match') ||
        msg.contains('no match') ||
        msg.contains('speech_timeout') ||
        msg.contains('speech timeout') ||
        msg.contains('aborted')) {
      return 'Didn\'t catch that. Try speaking a little slower.';
    }
    if (msg.contains('permission') || msg.contains('not allowed')) {
      return 'Microphone permission is required. Please enable it in settings.';
    }
    final permanent = (error?.permanent == true);
    return permanent
        ? 'Microphone is unavailable right now. Please try again.'
        : 'Listening stopped. Tap mic and try again.';
  }

  String _normalizeToken(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s,_-]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _compactToken(String value) {
    return _normalizeToken(value).replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  String _normalizeCategoryKey(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  bool _matchesSelectedCategory(Map<String, dynamic> product) {
    if (_selectedCategory == 'All') return true;

    final selectedKey = _normalizeCategoryKey(_selectedCategory);
    if (selectedKey.isEmpty) return true;

    final categoryCandidates = <String>{
      (product['category'] ?? '').toString(),
      (product['categoryName'] ?? '').toString(),
    };

    final rawSelectedCategories = product['selectedCategories'];
    if (rawSelectedCategories is List) {
      for (final item in rawSelectedCategories) {
        final value = item.toString().trim();
        if (value.isNotEmpty) categoryCandidates.add(value);
      }
    }

    for (final candidate in categoryCandidates) {
      final key = _normalizeCategoryKey(candidate);
      if (key.isEmpty) continue;
      if (key == selectedKey) return true;
    }

    return false;
  }

  bool _matchesSelectedTag(String rawTag) {
    final selected = _normalizeToken(_selectedTag ?? '');
    if (selected.isEmpty) return true;

    final compactSelected = _compactToken(selected);

    final normalizedTag = _normalizeToken(rawTag);
    if (normalizedTag.isEmpty) return false;

    final compactTag = _compactToken(normalizedTag);

    if (normalizedTag.contains(selected) || selected.contains(normalizedTag)) {
      return true;
    }

    if (compactSelected.isNotEmpty && compactTag.isNotEmpty) {
      if (compactTag.contains(compactSelected) ||
          compactSelected.contains(compactTag)) {
        return true;
      }
    }

    final tokens = normalizedTag
        .split(RegExp(r'[,|/&_-]+'))
        .map((t) => _normalizeToken(t))
        .where((t) => t.isNotEmpty);

    return tokens.any(
      (token) =>
          token.contains(selected) ||
          selected.contains(token) ||
          (_compactToken(token).isNotEmpty &&
              compactSelected.isNotEmpty &&
              (_compactToken(token).contains(compactSelected) ||
                  compactSelected.contains(_compactToken(token)))),
    );
  }

  String _tagSearchSource(Map<String, dynamic> product) {
    final primary = (product['tag'] ?? '').toString().trim();
    final rawTags = product['tags'];

    final multiTags = rawTags is List
        ? rawTags
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : rawTags is String
        ? rawTags
              .split(RegExp(r'[,|/&;]+'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];

    final merged = <String>{};
    if (primary.isNotEmpty) merged.add(primary);
    merged.addAll(multiTags);

    return merged.join(', ');
  }

  bool _matchesSearchQuery(Map<String, dynamic> product, String rawQuery) {
    final normalizedQuery = _normalizeToken(rawQuery);
    if (normalizedQuery.isEmpty) return true;

    final tokens = normalizedQuery
        .split(' ')
        .map(_normalizeToken)
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    final name = _normalizeToken(
      (product['name'] ?? product['title'] ?? product['productName'] ?? '')
          .toString(),
    );
    final brand = _normalizeToken(
      (product['brand'] ??
              product['brandName'] ??
              product['manufacturer'] ??
              '')
          .toString(),
    );
    final category = _normalizeToken(
      (product['category'] ?? product['categoryName'] ?? '').toString(),
    );
    final subCategory = _normalizeToken(
      (product['subCategory'] ?? product['subcategory'] ?? '').toString(),
    );
    final subSubCategory = _normalizeToken(
      (product['subSubCategory'] ?? product['subsubCategory'] ?? '').toString(),
    );
    final tag = _normalizeToken((product['tag'] ?? '').toString());
    final tags = _normalizeToken(_tagSearchSource(product));
    final description = _normalizeToken(
      (product['description'] ??
              product['shortDescription'] ??
              product['highlights'] ??
              '')
          .toString(),
    );
    final subtitle = _normalizeToken(
      (product['subtitle'] ??
              product['subTitle'] ??
              product['short_name'] ??
              '')
          .toString(),
    );
    final productType = _normalizeToken(
      (product['productType'] ?? product['type'] ?? '').toString(),
    );
    final sku = _normalizeToken(
      (product['sku'] ?? product['itemCode'] ?? product['code'] ?? '')
          .toString(),
    );

    String allValues(dynamic node) {
      if (node == null) return '';
      if (node is Map) {
        return node.values.map(allValues).join(' ');
      }
      if (node is Iterable) {
        return node.map(allValues).join(' ');
      }
      return node.toString();
    }

    final fallbackAllFields = _normalizeToken(allValues(product));

    final searchable =
        '$name $brand $category $subCategory $subSubCategory $tag $tags $description $subtitle $productType $sku $fallbackAllFields';
    final compactSearchable = _compactToken(searchable);

    // Require every query token to be present somewhere in searchable text.
    return tokens.every((token) {
      if (searchable.contains(token)) return true;
      final compactToken = _compactToken(token);
      if (compactToken.isEmpty) return false;
      return compactSearchable.contains(compactToken);
    });
  }

  int _searchScore(Map<String, dynamic> product, String rawQuery) {
    final query = _normalizeToken(rawQuery);
    if (query.isEmpty) return 0;

    final queryCompact = _compactToken(query);
    final queryTokens = query
        .split(' ')
        .map(_normalizeToken)
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    String norm(dynamic v) => _normalizeToken((v ?? '').toString());

    final name = norm(product['name'] ?? product['title'] ?? product['productName']);
    final brand = norm(product['brand'] ?? product['brandName'] ?? product['manufacturer']);
    final tags = norm(_tagSearchSource(product));
    final category = norm(product['category'] ?? product['categoryName']);
    final description = norm(
      product['description'] ?? product['shortDescription'] ?? product['highlights'],
    );

    int scoreField(String field, {required int exact, required int prefix, required int contains}) {
      if (field.isEmpty) return 0;
      var s = 0;
      if (field == query) s += exact;
      if (field.startsWith(query)) s += prefix;
      if (field.contains(query)) s += contains;

      final fieldCompact = _compactToken(field);
      if (queryCompact.isNotEmpty && fieldCompact == queryCompact) s += exact ~/ 2;
      if (queryCompact.isNotEmpty && fieldCompact.startsWith(queryCompact)) s += prefix ~/ 2;
      if (queryCompact.isNotEmpty && fieldCompact.contains(queryCompact)) s += contains ~/ 2;

      for (final token in queryTokens) {
        if (field.contains(token)) s += 8;
      }
      return s;
    }

    var score = 0;
    score += scoreField(name, exact: 220, prefix: 170, contains: 110);
    score += scoreField(brand, exact: 150, prefix: 120, contains: 80);
    score += scoreField(tags, exact: 120, prefix: 100, contains: 70);
    score += scoreField(category, exact: 90, prefix: 70, contains: 45);
    score += scoreField(description, exact: 40, prefix: 25, contains: 12);

    return score;
  }

  List<Map<String, dynamic>> _buildSourceProducts(
    HomeProvider home, {
    required bool shouldUseExpandedPool,
  }) {
    final sourceProducts = <Map<String, dynamic>>[]..addAll(_pagedProducts);
    if (!shouldUseExpandedPool) return sourceProducts;

    final byId = <String, Map<String, dynamic>>{};

    for (final product in sourceProducts) {
      final id = (product['id'] ?? '').toString().trim();
      if (id.isNotEmpty) byId[id] = product;
    }

    for (final product in home.productMaps) {
      final id = (product['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      byId.putIfAbsent(id, () => product);
    }

    return byId.values.toList(growable: false);
  }

  List<Map<String, dynamic>> _applyScopedFilters(
    List<Map<String, dynamic>> source,
  ) {
    return source
        .where((product) => _matchesSelectedCategory(product))
        .where((product) => _matchesSearchQuery(product, _searchQuery))
        .where((product) {
          if ((_selectedBrand ?? '').trim().isEmpty) return true;
          return (product['brand'] ?? '').toString().trim().toLowerCase() ==
              _selectedBrand!.trim().toLowerCase();
        })
        .where((product) {
          if ((_selectedTag ?? '').trim().isEmpty) return true;
          return _matchesSelectedTag(_tagSearchSource(product));
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _applyQueryFallbackIfNeeded(
    List<Map<String, dynamic>> source,
    List<Map<String, dynamic>> scopedProducts, {
    required bool hasQuery,
  }) {
    if (!(hasQuery && scopedProducts.isEmpty)) {
      return List<Map<String, dynamic>>.from(scopedProducts);
    }

    return source
        .where((product) => _matchesSearchQuery(product, _searchQuery))
        .toList(growable: false);
  }

  void _sortProductsForDisplay(
    List<Map<String, dynamic>> products, {
    required bool hasQuery,
  }) {
    if (hasQuery) {
      products.sort((a, b) {
        final scoreCmp = _searchScore(b, _searchQuery).compareTo(
          _searchScore(a, _searchQuery),
        );
        if (scoreCmp != 0) return scoreCmp;
        final aName = (a['name'] ?? '').toString().toLowerCase();
        final bName = (b['name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });
      return;
    }

    if (_sort == 'low') {
      products.sort((a, b) => (a['price'] as num).compareTo(b['price'] as num));
    } else if (_sort == 'high') {
      products.sort((a, b) => (b['price'] as num).compareTo(a['price'] as num));
    } else if (_sort == 'rating') {
      products.sort((a, b) => (b['rating'] as num).compareTo(a['rating'] as num));
    }
  }

  Future<void> _refreshProducts() async {
    await _loadFirstPage();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 280) {
      _loadNextPage();
    }
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        final normalized = status.toLowerCase();
        final listening = normalized.contains('listening');
        if (_isListening != listening) {
          setState(() => _isListening = listening);
        }
        if (!listening && _pendingVoiceSearch) {
          final spoken = (_activeTranscript?.value ?? '').trim();
          if (spoken.isNotEmpty &&
              spoken != 'Listening...' &&
              !spoken.startsWith('Didn\'t catch')) {
            _submitVoiceQuery(spoken);
            return;
          }
        }
        if (!listening &&
            _activeTranscript != null &&
            _activeTranscript!.value == 'Listening...') {
          _activeTranscript!.value =
              'Didn\'t catch that. Try speaking again clearly.';
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isListening = false);
        if (_activeTranscript != null) {
          final current = _activeTranscript!.value.trim();
          if (current.isEmpty || current == 'Listening...') {
            _activeTranscript!.value = _speechErrorMessage(error);
          }
        }
      },
    );

    if (!mounted) return;
    if (available) {
      try {
        final systemLocale = await _speech.systemLocale();
        final locales = await _speech.locales();
        if (systemLocale != null && systemLocale.localeId.trim().isNotEmpty) {
          _speechLocaleId = systemLocale.localeId;
        } else {
          final preferred = locales.where((l) {
            final id = l.localeId.toLowerCase();
            return id == 'en_in' || id.startsWith('en_');
          });
          _speechLocaleId =
              (preferred.isNotEmpty
                      ? preferred.first
                      : locales.isNotEmpty
                      ? locales.first
                      : null)
                  ?.localeId;
        }
      } catch (_) {
        // Keep locale null to let plugin choose device default.
      }
    }

    setState(() {
      _speechReady = available;
      if (!available) {
        _isListening = false;
      }
    });
  }

  Future<void> _toggleVoiceSearch() async {
    if (!_speechReady) {
      await _initSpeech();
    }

    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice search is unavailable on this device.'),
        ),
      );
      return;
    }

    if (_isListening) {
      _pendingVoiceSearch = false;
      await _speech.stop();
      _closeSpeechDialog();
      if (!mounted) return;
      setState(() => _isListening = false);
      return;
    }

    final transcript = ValueNotifier<String>('Listening...');
    _activeTranscript = transcript;
    _showSpeechDialog(
      title: 'Voice search',
      transcript: transcript,
      onSubmit: () {
        final spoken = transcript.value.trim();
        if (spoken.isEmpty || spoken == 'Listening...') return;
        _submitVoiceQuery(spoken);
      },
    );

    var launched = false;
    _pendingVoiceSearch = true;
    await _speech.cancel();
    final started = await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.search,
        partialResults: true,
        cancelOnError: false,
      ),
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 5),
      localeId: _speechLocaleId,
      onResult: (result) {
        if (!mounted || launched) return;
        final spoken = result.recognizedWords.trim();
        transcript.value = spoken.isEmpty ? 'Listening...' : spoken;
        _searchCtrl
          ..text = spoken
          ..selection = TextSelection.fromPosition(
            TextPosition(offset: spoken.length),
          );
        setState(() => _searchQuery = spoken);
        if (!result.finalResult || spoken.isEmpty) return;
        launched = true;
        _submitVoiceQuery(spoken);
      },
    );

    if (!started) {
      _pendingVoiceSearch = false;
      _closeSpeechDialog();
      _activeTranscript = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start voice input. Please try again.'),
        ),
      );
    }

    if (!mounted) return;
    setState(() => _isListening = started);
  }

  void _submitVoiceQuery(String spoken) {
    if (!_pendingVoiceSearch || !mounted) return;
    _pendingVoiceSearch = false;
    _closeSpeechDialog();
    _searchCtrl
      ..text = spoken
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: spoken.length),
      );
    setState(() {
      _isListening = false;
      _searchQuery = spoken;
    });
  }

  void _closeSpeechDialog() {
    if (!_speechDialogVisible || !mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    _speechDialogVisible = false;
    _activeTranscript = null;
  }

  void _showSpeechDialog({
    required String title,
    required ValueNotifier<String> transcript,
    required VoidCallback onSubmit,
  }) {
    if (!mounted || _speechDialogVisible) return;
    _speechDialogVisible = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: ValueListenableBuilder<String>(
            valueListenable: transcript,
            builder: (_, text, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isListening ? Icons.mic : Icons.mic_none_rounded,
                        color: _isListening
                            ? AppColors.primary
                            : AppColors.textHint,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(_isListening ? 'Listening...' : 'Tap mic to speak'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _speech.stop();
                _pendingVoiceSearch = false;
                _closeSpeechDialog();
                if (!mounted) return;
                setState(() => _isListening = false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: onSubmit, child: const Text('Search')),
          ],
        );
      },
    ).whenComplete(() {
      _speechDialogVisible = false;
      _activeTranscript = null;
      transcript.dispose();
    });
  }

  Future<void> _loadFirstPage() async {
    if (_isInitialLoading) return;
    setState(() {
      _isInitialLoading = true;
      _pagingError = null;
      _pagedProducts.clear();
      _lastProductDoc = null;
      _hasMoreProducts = true;
    });

    try {
      final page = await _firestoreService.getProductsPageFiltered(
        limit: _pageSize,
        category: null,
        brand: (_selectedBrand ?? '').trim().isEmpty ? null : _selectedBrand,
      );

      if (!mounted) return;
      setState(() {
        _pagedProducts
          ..clear()
          ..addAll(page.products.map((p) => p.toProductMap()));
        _lastProductDoc = page.lastDocument;
        _hasMoreProducts = page.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _pagingError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isInitialLoading = false);
        // Trigger a second-phase hydration AFTER initial loading flips false,
        // otherwise _hydrateScopeForSearchIfNeeded exits early.
        _hydrateScopeForSearchIfNeeded();
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isInitialLoading ||
        _isPageLoading ||
        _isSearchHydrating ||
        !_hasMoreProducts) {
      return;
    }

    setState(() {
      _isPageLoading = true;
    });

    try {
      final page = await _firestoreService.getProductsPageFiltered(
        limit: _pageSize,
        startAfterDoc: _lastProductDoc,
        category: null,
        brand: (_selectedBrand ?? '').trim().isEmpty ? null : _selectedBrand,
      );

      if (!mounted) return;
      setState(() {
        _pagedProducts.addAll(page.products.map((p) => p.toProductMap()));
        _lastProductDoc = page.lastDocument;
        _hasMoreProducts = page.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _pagingError = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isPageLoading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      _selectedCategory = widget.initialCategory!;
    }
    if (widget.initialBrand != null && widget.initialBrand!.trim().isNotEmpty) {
      _selectedBrand = widget.initialBrand!.trim();
    }
    if (widget.initialTag != null && widget.initialTag!.trim().isNotEmpty) {
      _selectedTag = widget.initialTag!.trim();
    }
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _searchQuery = widget.initialQuery!.trim();
      _searchCtrl.text = _searchQuery;
      _searchCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchQuery.length),
      );
    }

    _initSpeech();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirstPage());
  }

  @override
  void dispose() {
    _speech.stop();
    _scrollController.removeListener(_onScroll);
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final categories = [
      'All',
      ...home.categories.map((c) => (c['name'] ?? '').toString()),
    ].where((c) => c.trim().isNotEmpty).toSet().toList();

    if (_selectedCategory != 'All' && !categories.contains(_selectedCategory)) {
      _selectedCategory = 'All';
    }

    final hasQuery = _searchQuery.trim().isNotEmpty;
    final shouldUseExpandedPool =
        hasQuery ||
        (_selectedTag ?? '').trim().isNotEmpty ||
        (_selectedBrand ?? '').trim().isNotEmpty;

    final sourceProducts = _buildSourceProducts(
      home,
      shouldUseExpandedPool: shouldUseExpandedPool,
    );
    final scopedProducts = _applyScopedFilters(sourceProducts);
    final products = _applyQueryFallbackIfNeeded(
      sourceProducts,
      scopedProducts,
      hasQuery: hasQuery,
    );

    _sortProductsForDisplay(products, hasQuery: hasQuery);

    final displayedProducts = products;

    final title = (_selectedTag ?? '').trim().isNotEmpty
        ? _selectedTag!
        : (_selectedBrand ?? '').trim().isNotEmpty
        ? _selectedBrand!
        : 'Products';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFB69DF8),
                Color(0xFFC4B5FD),
                Color(0xFFDDD6FE),
                Color(0xFFEDE9FE),
                Colors.white,
              ],
              stops: [0.0, 0.18, 0.42, 0.70, 1.0],
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
            onPressed: _refreshProducts,
            tooltip: 'Refresh products',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.sort, color: AppColors.textPrimary),
              onSelected: (v) => setState(() => _sort = v),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'popular',
                  child: Text('Most Popular'),
                ),
                const PopupMenuItem(value: 'rating', child: Text('Top Rated')),
                const PopupMenuItem(
                  value: 'low',
                  child: Text('Price: Low to High'),
                ),
                const PopupMenuItem(
                  value: 'high',
                  child: Text('Price: High to Low'),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                setState(() => _searchQuery = v);
                _hydrateScopeForSearchIfNeeded();
              },
              decoration: InputDecoration(
                hintText: 'Search products...',
                hintStyle: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.textHint,
                  size: 20,
                ),
                suffixIconConstraints: BoxConstraints(
                  minWidth: _searchQuery.isNotEmpty ? 96 : 52,
                ),
                suffixIcon: SizedBox(
                  width: _searchQuery.isNotEmpty ? 96 : 52,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: AppColors.textHint,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                      IconButton(
                        onPressed: _toggleVoiceSearch,
                        icon: Icon(
                          _isListening ? Icons.mic : Icons.mic_none_rounded,
                          color: _isListening
                              ? AppColors.primary
                              : AppColors.textHint,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                filled: true,
                fillColor: AppColors.background,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Category chips
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemCount: categories.length,
              itemBuilder: (_, i) {
                final cat = categories[i];
                final selected = cat == _selectedCategory;
                return GestureDetector(
                  onTap: () async {
                    if (_selectedCategory == cat) return;
                    setState(() => _selectedCategory = cat);
                    await _loadFirstPage();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? AppColors.primary : AppColors.border,
                      ),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if ((_selectedBrand ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      'Brand: $_selectedBrand',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if ((_selectedTag ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Tag: $_selectedTag',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() => _selectedTag = null),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // Product count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Text(
                  _isSearchHydrating
                      ? '${displayedProducts.length} products • searching full catalog...'
                      : '${displayedProducts.length} products',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Grid
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshProducts,
              child: _isInitialLoading
                  ? GridView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.65,
                          ),
                      itemCount: 6,
                      itemBuilder: (_, _) => const ProductCardShimmer(),
                    )
                  : displayedProducts.isEmpty
                  ? ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 280,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  color: AppColors.textHint,
                                  size: 52,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No products found',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (_pagingError != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    _pagingError!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.textHint,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.65,
                          ),
                      itemCount: displayedProducts.length,
                      itemBuilder: (_, i) {
                        return ProductCard(product: displayedProducts[i]);
                      },
                    ),
            ),
          ),
          const StickyCartBar(),
        ],
      ),
      floatingActionButton: const SupportChatFab(),
    );
  }
}
