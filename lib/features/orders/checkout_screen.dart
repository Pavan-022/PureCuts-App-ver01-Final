import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/models/cart_model.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/core/theme/spacing.dart';
import 'package:purecuts/features/auth/providers/auth_provider.dart';
import 'package:purecuts/features/home/home_provider.dart';
import 'package:purecuts/features/orders/order_confirm_screen.dart';
import 'package:purecuts/features/products/product_detail_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  // Delivery charge constants
  static const int _puneDeliveryCharge = 19;
  static const int _otherDeliveryCharge = 30;
  static const int _freeDeliveryThreshold = 1000;
  static const int _handlingCharge = 5;
  static const int _smallCartThreshold = 99;
  static const int _smallCartCharge = 20;

  // All Pune pincodes
  static const Set<String> _punePincodes = {
    // Pune city core
    '411001',
    '411002',
    '411003',
    '411004',
    '411005',
    '411006',
    '411007',
    '411008',
    '411009',
    '411010',
    '411011',
    '411012',
    '411013',
    '411014',
    '411015',
    '411016',
    '411017',
    '411018',
    '411019',
    '411020',
    '411021',
    '411022',
    '411023',
    '411024',
    '411025',
    '411026',
    '411027',
    '411028',
    '411029',
    '411030',
    '411031',
    '411032',
    '411033',
    '411034',
    '411035',
    '411036',
    '411037',
    '411038',
    '411039',
    '411040',
    '411041',
    '411042',
    '411043',
    '411044',
    '411045',
    '411046',
    '411047',
    '411048',
    // Pimpri-Chinchwad areas
    '412001', '412108', '412115',
    // Hadapsar and suburbs
    '411050', '411051',
    // Outer Pune areas
    '413001', '413101', '413201', '413202',

    '412207',
  };

  String _selectedPaymentMethod = 'Cash on Delivery';

  final TextEditingController _line1Controller = TextEditingController();
  final TextEditingController _line2Controller = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _pincodeController = TextEditingController();
  final TextEditingController _mapLinkController = TextEditingController();
  final TextEditingController _receiverNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  final GlobalKey<FormState> _detailsFormKey = GlobalKey<FormState>();
  final List<Map<String, dynamic>> _savedAddresses = [];
  int _selectedAddressIndex = 0;
  bool _initialAddressPromptShown = false;

  void _applyAddressEntry(Map<String, dynamic> entry) {
    final address = (entry['deliveryAddress'] is Map)
        ? Map<String, dynamic>.from(entry['deliveryAddress'] as Map)
        : const <String, dynamic>{};
    final contact = (entry['contactDetails'] is Map)
        ? Map<String, dynamic>.from(entry['contactDetails'] as Map)
        : const <String, dynamic>{};

    _line1Controller.text = (address['line1'] ?? '').toString();
    _line2Controller.text = (address['line2'] ?? '').toString();
    _landmarkController.text = (address['landmark'] ?? '').toString();
    _cityController.text = (address['city'] ?? '').toString();
    _stateController.text = (address['state'] ?? '').toString();
    _pincodeController.text = (address['pincode'] ?? '').toString();
    _mapLinkController.text = (address['mapLink'] ?? '').toString();
    _receiverNameController.text = (contact['receiverName'] ?? '').toString();
    _phoneController.text = (contact['phone'] ?? '').toString();
  }

  void _hydrateAddressesFromUser(AuthProvider auth) {
    final user = auth.user;
    final savedDeliveryDetails =
        user?.deliveryDetails ?? const <String, dynamic>{};

    final addressesFromDelivery = (savedDeliveryDetails['addresses'] is List)
        ? (savedDeliveryDetails['addresses'] as List)
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList(growable: true)
        : <Map<String, dynamic>>[];

    if (addressesFromDelivery.isEmpty) {
      final fallbackAddress =
          user?.deliveryAddressDetails ?? const <String, dynamic>{};
      final fallbackContact = user?.contactDetails ?? const <String, dynamic>{};
      final hasFallback = (fallbackAddress['line1'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;
      if (hasFallback) {
        addressesFromDelivery.add({
          'deliveryAddress': Map<String, dynamic>.from(fallbackAddress),
          'contactDetails': Map<String, dynamic>.from(fallbackContact),
        });
      }
    }

    _savedAddresses
      ..clear()
      ..addAll(addressesFromDelivery);

    final preferredIndex =
        (savedDeliveryDetails['selectedAddressIndex'] as num?)?.toInt() ?? 0;
    _selectedAddressIndex = _savedAddresses.isEmpty
        ? 0
        : preferredIndex.clamp(0, _savedAddresses.length - 1);

    if (_savedAddresses.isNotEmpty) {
      _applyAddressEntry(_savedAddresses[_selectedAddressIndex]);
    }
  }

  @override
  void initState() {
    super.initState();

    final auth = context.read<AuthProvider>();
    _hydrateAddressesFromUser(auth);

    if (_savedAddresses.isEmpty) {
      final user = auth.user;
      _stateController.text = (user?.state ?? '').toString();
      _pincodeController.text = (user?.pincode ?? '').toString();
      _receiverNameController.text = (user?.ownerName ?? user?.name ?? '')
          .toString();
      _phoneController.text = (user?.phone ?? '').toString();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _initialAddressPromptShown) return;
        _initialAddressPromptShown = true;
        _openDetailsBottomSheet(blocking: true, editIndex: null);
      });
    }

    Future.microtask(() {
      final home = context.read<HomeProvider>();
      if (home.productMaps.isEmpty && !home.loading) {
        home.loadData();
      }
    });
  }

  @override
  void dispose() {
    _line1Controller.dispose();
    _line2Controller.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _mapLinkController.dispose();
    _receiverNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _baseProductId(String value) {
    final id = value.trim();
    if (id.isEmpty) return '';
    final sep = id.indexOf('::');
    if (sep <= 0) return id;
    return id.substring(0, sep);
  }

  String _normalizedPhone(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'\D'), '');
    if (cleaned.length == 12 && cleaned.startsWith('91')) {
      return cleaned.substring(2);
    }
    return cleaned;
  }

  bool _validPhone(String value) {
    final normalized = _normalizedPhone(value);
    return normalized.length == 10;
  }

  bool _isDeliveryOrContactMissing() {
    return _line1Controller.text.trim().isEmpty ||
        _cityController.text.trim().isEmpty ||
        _stateController.text.trim().isEmpty ||
        _pincodeController.text.trim().isEmpty ||
        _receiverNameController.text.trim().isEmpty ||
        !_validPhone(_phoneController.text);
  }

  Map<String, dynamic> _deliveryAddressMap() {
    return {
      'line1': _line1Controller.text.trim(),
      'line2': _line2Controller.text.trim(),
      'landmark': _landmarkController.text.trim(),
      'city': _cityController.text.trim(),
      'state': _stateController.text.trim(),
      'pincode': _pincodeController.text.trim(),
      'country': 'India',
      'mapLink': _mapLinkController.text.trim(),
    };
  }

  Map<String, dynamic> _contactDetailsMap() {
    final cleanedPhone = _normalizedPhone(_phoneController.text);
    return {
      'receiverName': _receiverNameController.text.trim(),
      'phone': cleanedPhone,
    };
  }

  int _itemTotal(CartModel cart) => cart.totalPrice;

  int _smallCartChargeAmount(int itemTotal) {
    return itemTotal < _smallCartThreshold ? _smallCartCharge : 0;
  }

  /// Check if delivery location is Pune based on pincode
  bool _isPuneDelivery() {
    final pincode = _pincodeController.text.trim();
    return _punePincodes.contains(pincode);
  }

  /// Calculate delivery charge based on location and order value
  int _calculateDeliveryCharge(int itemTotal) {
    // Free delivery for orders >= ₹1000
    if (itemTotal >= _freeDeliveryThreshold) {
      return 0;
    }
    // Location-based delivery charge
    return _isPuneDelivery() ? _puneDeliveryCharge : _otherDeliveryCharge;
  }

  int _grandTotal(CartModel cart) {
    final itemTotal = _itemTotal(cart);
    final deliveryCharge = _calculateDeliveryCharge(itemTotal);
    return itemTotal +
        deliveryCharge +
        _handlingCharge +
        _smallCartChargeAmount(itemTotal);
  }

  List<Map<String, dynamic>> _recommendations({
    required CartModel cart,
    required HomeProvider home,
  }) {
    final allProducts = home.productMaps;
    if (allProducts.isEmpty || cart.items.isEmpty) return const [];

    final cartIds = cart.items
        .map((item) => _baseProductId(item.id))
        .where((id) => id.isNotEmpty)
        .toSet();

    final cartProducts = allProducts
        .where(
          (p) => cartIds.contains(_baseProductId((p['id'] ?? '').toString())),
        )
        .toList(growable: false);

    final cartTags = <String>{};
    final cartCategories = <String>{};

    for (final product in cartProducts) {
      final tag = (product['tag'] ?? '').toString().trim().toLowerCase();
      if (tag.isNotEmpty) cartTags.add(tag);
      final tags = product['tags'];
      if (tags is List) {
        for (final t in tags) {
          final normalized = t.toString().trim().toLowerCase();
          if (normalized.isNotEmpty) cartTags.add(normalized);
        }
      }
      final category = (product['category'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (category.isNotEmpty) cartCategories.add(category);
    }

    int scoreOf(Map<String, dynamic> product) {
      final productTagSet = <String>{};
      final single = (product['tag'] ?? '').toString().trim().toLowerCase();
      if (single.isNotEmpty) productTagSet.add(single);
      final tags = product['tags'];
      if (tags is List) {
        for (final t in tags) {
          final normalized = t.toString().trim().toLowerCase();
          if (normalized.isNotEmpty) productTagSet.add(normalized);
        }
      }

      final category = (product['category'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      final tagMatches = productTagSet.where(cartTags.contains).length;
      final categoryMatch = cartCategories.contains(category) ? 1 : 0;
      final rating = (product['rating'] as num?)?.toDouble() ?? 0;
      final reviews = (product['reviews'] as num?)?.toInt() ?? 0;

      return (tagMatches * 10000) +
          (categoryMatch * 1000) +
          (rating * 100).round() +
          reviews;
    }

    final candidates = allProducts
        .where(
          (p) => !cartIds.contains(_baseProductId((p['id'] ?? '').toString())),
        )
        .toList();

    candidates.sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));

    final primary = candidates
        .where((p) {
          final category = (p['category'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final tag = (p['tag'] ?? '').toString().trim().toLowerCase();
          final tags = p['tags'] is List
              ? (p['tags'] as List)
                    .map((e) => e.toString().trim().toLowerCase())
                    .toSet()
              : <String>{};
          final tagMatch =
              cartTags.contains(tag) || tags.any(cartTags.contains);
          final categoryMatch = cartCategories.contains(category);
          return tagMatch || categoryMatch;
        })
        .take(6)
        .toList(growable: true);

    if (primary.length < 6) {
      final already = primary
          .map((e) => _baseProductId((e['id'] ?? '').toString()))
          .toSet();
      for (final candidate in candidates) {
        final id = _baseProductId((candidate['id'] ?? '').toString());
        if (already.contains(id)) continue;
        primary.add(candidate);
        if (primary.length >= 6) break;
      }
    }

    return primary.take(6).toList(growable: false);
  }

  Future<void> _openDetailsBottomSheet({
    bool blocking = false,
    int? editIndex,
  }) async {
    if (editIndex != null &&
        editIndex >= 0 &&
        editIndex < _savedAddresses.length) {
      _applyAddressEntry(_savedAddresses[editIndex]);
    } else {
      _line1Controller.clear();
      _line2Controller.clear();
      _landmarkController.clear();
      _cityController.clear();
      _mapLinkController.clear();
      if (_savedAddresses.isEmpty) {
        final user = context.read<AuthProvider>().user;
        _stateController.text = (user?.state ?? _stateController.text)
            .toString();
        _pincodeController.text = (user?.pincode ?? _pincodeController.text)
            .toString();
        _receiverNameController.text =
            (user?.ownerName ?? user?.name ?? _receiverNameController.text)
                .toString();
        _phoneController.text = (user?.phone ?? _phoneController.text)
            .toString();
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: !blocking,
      enableDrag: !blocking,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.round),
        ),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom:
                MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
          ),
          child: Form(
            key: _detailsFormKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Add your delivery details',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'This is required once for smoother checkout next time.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _textField(_line1Controller, 'Address line 1*'),
                  const SizedBox(height: AppSpacing.md),
                  _textField(_line2Controller, 'Address line 2'),
                  const SizedBox(height: AppSpacing.md),
                  _textField(_landmarkController, 'Landmark'),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(child: _textField(_cityController, 'City*')),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: _textField(_stateController, 'State*')),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _textField(
                    _pincodeController,
                    'Pincode*',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _textField(_mapLinkController, 'Google maps link (optional)'),
                  const SizedBox(height: AppSpacing.md),
                  _textField(_receiverNameController, 'Receiver name*'),
                  const SizedBox(height: AppSpacing.md),
                  _textField(
                    _phoneController,
                    'Phone number*',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (_line1Controller.text.trim().isEmpty ||
                            _cityController.text.trim().isEmpty ||
                            _stateController.text.trim().isEmpty ||
                            _pincodeController.text.trim().isEmpty ||
                            _receiverNameController.text.trim().isEmpty ||
                            !_validPhone(_phoneController.text)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please enter valid delivery/contact details.',
                              ),
                            ),
                          );
                          return;
                        }

                        final auth = context.read<AuthProvider>();
                        final newEntry = {
                          'deliveryAddress': _deliveryAddressMap(),
                          'contactDetails': _contactDetailsMap(),
                        };

                        final updatedList = List<Map<String, dynamic>>.from(
                          _savedAddresses,
                        );

                        int selectedIdx;
                        if (editIndex != null &&
                            editIndex >= 0 &&
                            editIndex < updatedList.length) {
                          updatedList[editIndex] = newEntry;
                          selectedIdx = editIndex;
                        } else {
                          updatedList.add(newEntry);
                          selectedIdx = updatedList.length - 1;
                        }

                        final saved = await auth.updateCheckoutDeliveryDetails(
                          deliveryAddress:
                              newEntry['deliveryAddress']
                                  as Map<String, dynamic>,
                          contactDetails:
                              newEntry['contactDetails']
                                  as Map<String, dynamic>,
                          addresses: updatedList,
                          selectedAddressIndex: selectedIdx,
                        );

                        if (!mounted) return;
                        if (!saved) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Unable to save details. Please try again.',
                              ),
                            ),
                          );
                          return;
                        }

                        setState(() {
                          _savedAddresses
                            ..clear()
                            ..addAll(updatedList);
                          _selectedAddressIndex = selectedIdx;
                        });
                        Navigator.of(sheetContext).pop();
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text('Delivery details saved.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Text('Save details'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _selectAddress(int index) async {
    if (index < 0 || index >= _savedAddresses.length) return;
    _applyAddressEntry(_savedAddresses[index]);

    final selectedEntry = _savedAddresses[index];
    final auth = context.read<AuthProvider>();
    await auth.updateCheckoutDeliveryDetails(
      deliveryAddress:
          selectedEntry['deliveryAddress'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
      contactDetails:
          selectedEntry['contactDetails'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
      addresses: _savedAddresses,
      selectedAddressIndex: index,
    );

    if (!mounted) return;
    setState(() {
      _selectedAddressIndex = index;
    });
  }

  Widget _textField(
    TextEditingController controller,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.textHint),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 14,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
      ),
    );
  }

  Future<void> _placeOrder({
    required CartModel cart,
    required HomeProvider home,
  }) async {
    if (_isDeliveryOrContactMissing()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add delivery/contact details before placing order.',
          ),
        ),
      );
      return;
    }

    final itemTotal = _itemTotal(cart);
    final deliveryCharge = _calculateDeliveryCharge(itemTotal);
    final grandTotal = _grandTotal(cart);
    final smallCartCharge = _smallCartChargeAmount(itemTotal);

    // ── Confirmation dialog ──────────────────────────────────────────────────
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text(
          'Confirm order',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please review your order before placing it.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.md),
            // Summary box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F2FF),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: const Color(0xFFE3D4F4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Items',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${cart.items.length} item${cart.items.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Delivery charge row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Delivery',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        deliveryCharge == 0 ? 'FREE' : '₹$deliveryCharge',
                        style: TextStyle(
                          color: deliveryCharge == 0
                              ? Colors.green
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  if (smallCartCharge > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Small cart charge',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '₹$smallCartCharge',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Divider(height: 1),
                  ),
                  // Grand total
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '₹$grandTotal',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Payment method
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Payment',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        _selectedPaymentMethod,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                    ),
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text(
                    'Go back',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                    ),
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text(
                    'Confirm',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // User cancelled — do nothing
    if (confirmed != true || !mounted) return;
    // ── End confirmation dialog ──────────────────────────────────────────────

    final auth = context.read<AuthProvider>();
    final deliveryAddress = _deliveryAddressMap();
    final contactDetails = _contactDetailsMap();

    final saved = await auth.updateCheckoutDeliveryDetails(
      deliveryAddress: deliveryAddress,
      contactDetails: contactDetails,
    );
    if (!saved) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to save delivery details. Please try again.'),
          ),
        );
      }
      return;
    }

    final allProducts = home.productMaps;
    final productById = <String, Map<String, dynamic>>{
      for (final p in allProducts)
        _baseProductId((p['id'] ?? '').toString()): p,
    };

    final orderedItems = cart.items
        .map((item) {
          final product =
              productById[_baseProductId(item.id)] ?? const <String, dynamic>{};
          return {
            'id': item.id,
            'name': item.name,
            'brand': item.brand,
            'image': item.image,
            'price': item.price,
            'originalPrice': (product['originalPrice'] ?? item.price),
            'size': (product['size'] ?? '').toString(),
            'tag': (product['tag'] ?? '').toString(),
            'tags': (product['tags'] is List)
                ? List<String>.from(product['tags'])
                : <String>[],
            'category': (product['category'] ?? '').toString(),
            'subCategory': (product['subCategory'] ?? '').toString(),
            'quantity': item.quantity,
          };
        })
        .toList(growable: false);

    final deliveryChargeValue = _calculateDeliveryCharge(itemTotal);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderConfirmScreen(
          total: grandTotal,
          orderedItems: orderedItems,
          deliveryAddress: deliveryAddress,
          contactDetails: contactDetails,
          paymentMethod: _selectedPaymentMethod,
          billDetails: {
            'itemTotal': itemTotal,
            'deliveryCharge': deliveryChargeValue,
            'handlingCharge': 0,
            'grandTotal': grandTotal,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartModel>();
    final home = context.watch<HomeProvider>();

    if (cart.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: const Center(child: Text('Your cart is empty')),
      );
    }

    final itemTotal = _itemTotal(cart);
    final grandTotal = _grandTotal(cart);
    final recommendations = _recommendations(cart: cart, home: home);

    final addressSummary = [
      _line1Controller.text.trim(),
      _line2Controller.text.trim(),
      _cityController.text.trim(),
      _stateController.text.trim(),
      _pincodeController.text.trim(),
    ].where((e) => e.isNotEmpty).join(', ');

    return Scaffold(
      backgroundColor: const Color(0xFFF1E5FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1E5FF),
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF0DEFF), Color(0xFFE8D2FF)],
            ),
          ),
        ),
        title: const Text(
          'Checkout',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEFDCFF), Color(0xFFE6CEFF), Color(0xFFF4E8FF)],
          ),
        ),
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                188,
              ),
              children: [
                _sectionCard(
                  title: 'Selected items',
                  child: Column(
                    children: cart.items.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.lg,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.lg,
                                    ),
                                    child: Image.network(
                                      item.image,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.image_outlined,
                                        color: AppColors.textHint,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        '₹${item.price} each',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '₹${item.price * item.quantity}',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: () => context
                                          .read<CartModel>()
                                          .remove(item.id),
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.md,
                                      ),
                                      child: const SizedBox(
                                        width: 34,
                                        child: Icon(
                                          Icons.remove_rounded,
                                          color: AppColors.textSecondary,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 24,
                                      child: Text(
                                        '${item.quantity}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () =>
                                          context.read<CartModel>().add({
                                            'id': item.id,
                                            'name': item.name,
                                            'brand': item.brand,
                                            'image': item.image,
                                            'price': item.price,
                                          }),
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.md,
                                      ),
                                      child: const SizedBox(
                                        width: 34,
                                        child: Icon(
                                          Icons.add_rounded,
                                          color: AppColors.textSecondary,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _sectionCard(
                  title: 'You might also like',
                  child: recommendations.isEmpty
                      ? const Text(
                          'No related products yet.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        )
                      : GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: recommendations.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: AppSpacing.md,
                                crossAxisSpacing: AppSpacing.md,
                                childAspectRatio: 0.7,
                              ),
                          itemBuilder: (_, i) {
                            final p = recommendations[i];
                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ProductDetailScreen(product: p),
                                  ),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.lg,
                                    ),
                                    border: Border.all(
                                      color: AppColors.divider,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.sm,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Center(
                                            child: Image.network(
                                              (p['image'] ?? '').toString(),
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(
                                                    Icons.image_outlined,
                                                    color: AppColors.textHint,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        Text(
                                          (p['name'] ?? '').toString(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '₹${p['price']}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: AppColors.textPrimary,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.xs,
                                            ),
                                            InkWell(
                                              onTap: () => context
                                                  .read<CartModel>()
                                                  .add(p),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppRadius.sm,
                                                  ),
                                              child: Container(
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 38,
                                                    ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        AppRadius.sm,
                                                      ),
                                                  border: Border.all(
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                                child: const Text(
                                                  'ADD',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: AppColors.primary,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _sectionCard(
                  title: 'Apply promo code',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.sell_outlined,
                        color: AppColors.textHint,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: TextField(
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter promo code',
                            hintStyle: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {},
                        child: const Text(
                          'Apply',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _sectionCard(
                  title: 'Bill details',
                  child: Column(
                    children: [
                      _billRow('Items total', '₹$itemTotal'),
                      const SizedBox(height: AppSpacing.sm),
                      _billRow(
                        'Delivery charge',
                        _calculateDeliveryCharge(itemTotal) == 0
                            ? 'FREE'
                            : '₹${_calculateDeliveryCharge(itemTotal)}',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _billRow('Handling charge', '₹0'),
                      const SizedBox(height: AppSpacing.sm),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                        child: Divider(height: 1),
                      ),
                      _billRow('Grand total', '₹$grandTotal', bold: true),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _sectionCard(
                  title: 'Delivery section',
                  trailing: TextButton(
                    onPressed: () => _openDetailsBottomSheet(editIndex: null),
                    child: const Text('Add new address'),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_savedAddresses.isNotEmpty) ...[
                        const Text(
                          'Saved addresses',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Column(
                          children: List.generate(_savedAddresses.length, (
                            index,
                          ) {
                            final entry = _savedAddresses[index];
                            final address =
                                entry['deliveryAddress']
                                    as Map<String, dynamic>? ??
                                const <String, dynamic>{};
                            final contact =
                                entry['contactDetails']
                                    as Map<String, dynamic>? ??
                                const <String, dynamic>{};
                            final summary = [
                              (address['line1'] ?? '').toString(),
                              (address['line2'] ?? '').toString(),
                              (address['city'] ?? '').toString(),
                              (address['state'] ?? '').toString(),
                              (address['pincode'] ?? '').toString(),
                            ].where((e) => e.trim().isNotEmpty).join(', ');
                            final isSelected = index == _selectedAddressIndex;

                            return InkWell(
                              onTap: () => _selectAddress(index),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary.withOpacity(0.08)
                                      : AppColors.surface,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary.withOpacity(0.35)
                                        : AppColors.divider,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.textHint,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (contact['receiverName'] ?? '')
                                                    .toString()
                                                    .trim()
                                                    .isEmpty
                                                ? 'Address ${index + 1}'
                                                : (contact['receiverName'] ??
                                                          '')
                                                      .toString(),
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            summary.isEmpty
                                                ? 'No address details'
                                                : summary,
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => _openDetailsBottomSheet(
                                        editIndex: index,
                                      ),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 6),
                      ],
                      const Text(
                        'Delivery address',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _savedAddresses.isEmpty
                            ? (addressSummary.isEmpty
                                  ? 'Not added yet'
                                  : addressSummary)
                            : [
                                (_savedAddresses[_selectedAddressIndex]['deliveryAddress']
                                            as Map<String, dynamic>? ??
                                        const <String, dynamic>{})['line1']
                                    .toString(),
                                (_savedAddresses[_selectedAddressIndex]['deliveryAddress']
                                            as Map<String, dynamic>? ??
                                        const <String, dynamic>{})['line2']
                                    .toString(),
                                (_savedAddresses[_selectedAddressIndex]['deliveryAddress']
                                            as Map<String, dynamic>? ??
                                        const <String, dynamic>{})['city']
                                    .toString(),
                                (_savedAddresses[_selectedAddressIndex]['deliveryAddress']
                                            as Map<String, dynamic>? ??
                                        const <String, dynamic>{})['state']
                                    .toString(),
                                (_savedAddresses[_selectedAddressIndex]['deliveryAddress']
                                            as Map<String, dynamic>? ??
                                        const <String, dynamic>{})['pincode']
                                    .toString(),
                              ].where((e) => e.trim().isNotEmpty).join(', '),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Text(
                        'Contact details',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _savedAddresses.isEmpty
                            ? '${_receiverNameController.text.trim()} • ${_phoneController.text.trim()}'
                            : '${((_savedAddresses[_selectedAddressIndex]['contactDetails'] as Map<String, dynamic>? ?? const <String, dynamic>{})['receiverName'] ?? '').toString().trim()} • ${((_savedAddresses[_selectedAddressIndex]['contactDetails'] as Map<String, dynamic>? ?? const <String, dynamic>{})['phone'] ?? '').toString().trim()}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  MediaQuery.of(context).padding.bottom + AppSpacing.md,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFF6EEFF),
                  border: Border(top: BorderSide(color: AppColors.divider)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final methods = ['Cash on Delivery'];
                        final selected = await showModalBottomSheet<String>(
                          context: context,
                          builder: (_) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: methods
                                  .map(
                                    (method) => ListTile(
                                      title: Text(method),
                                      trailing: _selectedPaymentMethod == method
                                          ? const Icon(
                                              Icons.check_circle,
                                              color: AppColors.primary,
                                            )
                                          : null,
                                      onTap: () =>
                                          Navigator.pop(context, method),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        );
                        if (selected != null && mounted) {
                          setState(() => _selectedPaymentMethod = selected);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.md,
                        ),
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_outlined,
                              color: AppColors.textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedPaymentMethod,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_up,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.xl,
                                ),
                              ),
                            ),
                            onPressed: () =>
                                _placeOrder(cart: cart, home: home),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '₹$grandTotal • Place Order',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF6FF),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: const Color(0xFFE3D4F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }

  Widget _billRow(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: bold ? 20 : 14,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
