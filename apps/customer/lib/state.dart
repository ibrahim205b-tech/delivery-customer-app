import 'package:flutter/foundation.dart';
import 'package:wasel_core/wasel_core.dart';

class CartLine {
  CartLine(this.product, this.qty, [this.note = '']);
  final Product product;
  int qty;
  String note;
  int get total => product.price * qty;
}

/// حالة تطبيق المستهلك: الأقسام، العناوين، المنطقة، المفضلة، السلة.
class CustomerState extends ChangeNotifier {
  List<MerchantCategory> categories = [];
  List<ServiceArea> areas = [];
  List<Address> addresses = [];
  Set<String> favorites = {};
  String? selectedAddressId;
  String? selectedAreaId;
  LatLng? deviceLocation;
  bool loaded = false;
  Object? loadError;

  // السلة: من محل واحد
  Merchant? cartMerchant;
  final List<CartLine> cart = [];
  String cartNote = '';
  String cartRef = newClientRef(); // مرجع ثابت للطلب حتى لو انضغط الزر مرتين
  String? cartPromo; // كود خصم مقبول من الخادم
  bool cartUseWallet = false;

  /// الرصيد والنقاط وكود الدعوة. null قبل التحميل أو إذا الخادم ما يدعم المكافآت.
  Rewards? rewards;

  Future<void> loadRewards() async {
    try {
      rewards = await customerApi.rewards();
      notifyListeners();
    } catch (_) {
      // المكافآت إضافة: فشلها ما يوقف التطبيق
    }
  }

  void setRewards(Rewards r) {
    rewards = r;
    notifyListeners();
  }

  List<Map<String, dynamic>> get cartItemsPayload => cart.map((l) => {'product_id': l.product.id, 'qty': l.qty, 'note': l.note}).toList();

  void setCartPromo(String? code) {
    cartPromo = (code == null || code.trim().isEmpty) ? null : code.trim().toUpperCase();
    notifyListeners();
  }

  void setCartUseWallet(bool v) {
    cartUseWallet = v;
    notifyListeners();
  }

  Address? get selectedAddress {
    if (addresses.isEmpty) return null;
    return addresses.firstWhere((a) => a.id == selectedAddressId, orElse: () => addresses.first);
  }

  ServiceArea? get selectedArea => areas.where((a) => a.id == selectedAreaId).firstOrNull;

  /// النقطة المرجعية لحساب "القريب": العنوان المختار، وإلا موقع الجهاز
  LatLng? get referencePoint {
    final a = selectedAddress;
    if (a != null) return LatLng(a.lat, a.lng);
    return deviceLocation;
  }

  Future<void> load() async {
    loadError = null;
    try {
      final r = await Future.wait([catalogApi.categories(), catalogApi.areas(), customerApi.addresses(), customerApi.favoriteIds()]);
      categories = r[0] as List<MerchantCategory>;
      areas = r[1] as List<ServiceArea>;
      addresses = r[2] as List<Address>;
      favorites = r[3] as Set<String>;
      selectedAddressId ??= addresses.where((a) => a.isDefault).firstOrNull?.id ?? addresses.firstOrNull?.id;
      _guessArea();
      loaded = true;
    } catch (e) {
      loadError = e;
    }
    notifyListeners();
    loadRewards();
    if (addresses.isEmpty && deviceLocation == null) {
      final l = await currentLocation();
      if (l.position != null) {
        deviceLocation = l.position;
        _guessArea();
        notifyListeners();
      }
    }
  }

  /// يختار المنطقة الأقرب للنقطة المرجعية إذا ما مختار منطقة
  void _guessArea() {
    if (selectedAreaId != null || areas.isEmpty) return;
    final p = referencePoint;
    if (p == null) return;
    ServiceArea? best;
    var bestD = double.infinity;
    for (final a in areas.where((a) => a.isActive)) {
      final d = distanceKm(p.latitude, p.longitude, a.centerLat, a.centerLng);
      if (d <= a.radiusKm && d < bestD) {
        best = a;
        bestD = d;
      }
    }
    selectedAreaId = best?.id;
  }

  void selectArea(String? id) {
    selectedAreaId = id;
    notifyListeners();
  }

  void selectAddress(String id) {
    selectedAddressId = id;
    notifyListeners();
  }

  Future<void> reloadAddresses() async {
    addresses = await customerApi.addresses();
    if (!addresses.any((a) => a.id == selectedAddressId)) selectedAddressId = addresses.firstOrNull?.id;
    notifyListeners();
  }

  Future<void> toggleFavorite(String merchantId) async {
    final fav = !favorites.contains(merchantId);
    fav ? favorites.add(merchantId) : favorites.remove(merchantId);
    notifyListeners();
    try {
      await customerApi.setFavorite(merchantId, fav);
    } catch (e) {
      fav ? favorites.remove(merchantId) : favorites.add(merchantId);
      notifyListeners();
      rethrow;
    }
  }

  // ---------------- السلة ----------------
  int qtyOf(String productId) => cart.where((l) => l.product.id == productId).firstOrNull?.qty ?? 0;
  int get cartCount => cart.fold(0, (a, l) => a + l.qty);
  int get cartSubtotal => cart.fold(0, (a, l) => a + l.total);

  /// يرجع false إذا المنتج من محل ثاني (يحتاج تأكيد تفريغ السلة)
  bool add(Merchant m, Product p) {
    if (cartMerchant != null && cartMerchant!.id != m.id && cart.isNotEmpty) return false;
    cartMerchant = m;
    final l = cart.where((l) => l.product.id == p.id).firstOrNull;
    if (l == null) {
      cart.add(CartLine(p, 1));
    } else if (l.qty < 99) {
      l.qty++;
    }
    notifyListeners();
    return true;
  }

  void remove(Product p) {
    final l = cart.where((l) => l.product.id == p.id).firstOrNull;
    if (l == null) return;
    l.qty--;
    if (l.qty <= 0) cart.remove(l);
    if (cart.isEmpty) cartMerchant = null;
    notifyListeners();
  }

  void setLineNote(Product p, String note) {
    cart.where((l) => l.product.id == p.id).firstOrNull?.note = note;
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    cartMerchant = null;
    cartNote = '';
    cartRef = newClientRef();
    cartPromo = null;
    cartUseWallet = false;
    notifyListeners();
  }

  Future<Order> placeOrder() async {
    final m = cartMerchant!;
    final a = selectedAddress!;
    final order = await customerApi.placeOrder(
      merchantId: m.id,
      addressId: a.id,
      items: cartItemsPayload,
      note: cartNote,
      clientRef: cartRef,
      promoCode: cartPromo,
      useWallet: cartUseWallet,
    );
    final spentRewards = cartUseWallet;
    clearCart();
    if (spentRewards) loadRewards();
    return order;
  }
}
