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
  String? _pagingError;

  String _searchQuery = '';

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

  bool _matchesSelectedTag(String rawTag) {
    final selected = _normalizeToken(_selectedTag ?? '');
    if (selected.isEmpty) return true;

    final normalizedTag = _normalizeToken(rawTag);
    if (normalizedTag.isEmpty) return false;

    if (normalizedTag.contains(selected) || selected.contains(normalizedTag)) {
      return true;
    }

    final tokens = normalizedTag
        .split(RegExp(r'[,|/&_-]+'))
        .map((t) => _normalizeToken(t))
        .where((t) => t.isNotEmpty);

    return tokens.any(
      (token) => token.contains(selected) || selected.contains(token),
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
        : <String>[];

    final merged = <String>{};
    if (primary.isNotEmpty) merged.add(primary);
    merged.addAll(multiTags);

    return merged.join(', ');
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
            builder: (_, text, __) {
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
        category: _selectedCategory == 'All' ? null : _selectedCategory,
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
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isInitialLoading || _isPageLoading || !_hasMoreProducts) return;

    setState(() {
      _isPageLoading = true;
    });

    try {
      final page = await _firestoreService.getProductsPageFiltered(
        limit: _pageSize,
        startAfterDoc: _lastProductDoc,
        category: _selectedCategory == 'All' ? null : _selectedCategory,
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

    final products = _pagedProducts
        .where((p) {
          if (_searchQuery.trim().isEmpty) return true;
          final search = _normalizeToken(_searchQuery);
          final name = _normalizeToken((p['name'] ?? '').toString());
          final brand = _normalizeToken((p['brand'] ?? '').toString());
          final category = _normalizeToken((p['category'] ?? '').toString());
          final text = '$name $brand $category';
          return text.contains(search);
        })
        .where((p) {
          if ((_selectedBrand ?? '').trim().isEmpty) return true;
          return (p['brand'] ?? '').toString().trim().toLowerCase() ==
              _selectedBrand!.trim().toLowerCase();
        })
        .where((p) {
          if ((_selectedTag ?? '').trim().isEmpty) return true;
          return _matchesSelectedTag(_tagSearchSource(p));
        })
        .toList();

    if (_sort == 'low') {
      products.sort((a, b) => (a['price'] as num).compareTo(b['price'] as num));
    } else if (_sort == 'high') {
      products.sort((a, b) => (b['price'] as num).compareTo(a['price'] as num));
    } else if (_sort == 'rating') {
      products.sort(
        (a, b) => (b['rating'] as num).compareTo(a['rating'] as num),
      );
    }

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
              onChanged: (v) => setState(() => _searchQuery = v),
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
                  '${displayedProducts.length} products',
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
