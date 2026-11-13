import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'config.dart';

const _uuid = Uuid();
String newClientRef() => _uuid.v4();

String get _uid => db.auth.currentUser!.id;

// =====================================================================
// الكتالوج: الأقسام، المناطق، المحلات، المنتجات، العروض
// =====================================================================
class CatalogApi {
  const CatalogApi();

  Future<List<MerchantCategory>> categories() async {
    final r = await db.from('merchant_categories').select().eq('is_active', true).order('sort', ascending: true);
    return r.map(MerchantCategory.fromJson).toList();
  }

  Future<List<ServiceArea>> areas() async {
    final r = await db.from('service_areas').select().order('name', ascending: true);
    return r.map(ServiceArea.fromJson).toList();
  }

  Future<List<Merchant>> merchants({String? categoryId, String? areaId, String? search, int limit = 100}) async {
    var q = db.from('merchants').select().eq('status', 'approved');
    if (categoryId != null) q = q.eq('category_id', categoryId);
    if (areaId != null) q = q.eq('area_id', areaId);
    if (search != null && search.trim().isNotEmpty) q = q.ilike('name', '%${search.trim()}%');
    final r = await q.order('order_count', ascending: false).limit(limit);
    return r.map(Merchant.fromJson).toList();
  }

  Future<Merchant?> merchant(String id) async {
    final r = await db.from('merchants').select().eq('id', id).maybeSingle();
    return r == null ? null : Merchant.fromJson(r);
  }

  Future<List<ProductCategory>> productCategories(String merchantId) async {
    final r = await db.from('product_categories').select().eq('merchant_id', merchantId).order('sort', ascending: true).order('name', ascending: true);
    return r.map(ProductCategory.fromJson).toList();
  }

  Future<List<Product>> products(String merchantId, {bool onlyAvailable = false}) async {
    var q = db.from('products').select('*, product_images(url, sort)').eq('merchant_id', merchantId);
    if (onlyAvailable) q = q.eq('is_available', true);
    final r = await q.order('sort', ascending: true).order('name', ascending: true);
    return r.map(Product.fromJson).toList();
  }

  /// بحث شامل: محلات + منتجات بالاسم (فقط المعتمد يظهر بسبب RLS)
  Future<({List<Merchant> merchants, List<(Product, Merchant)> products})> search(String text) async {
    final t = text.trim();
    if (t.isEmpty) return (merchants: <Merchant>[], products: <(Product, Merchant)>[]);
    final ms = await merchants(search: t, limit: 20);
    final pr = await db
        .from('products')
        .select('*, product_images(url, sort), merchants!inner(*)')
        .ilike('name', '%$t%')
        .eq('is_available', true)
        .eq('merchants.status', 'approved')
        .limit(30);
    return (
      merchants: ms,
      products: pr.map((j) => (Product.fromJson(j), Merchant.fromJson(j['merchants'] as Json))).toList(),
    );
  }

  Future<List<Promotion>> activePromotions() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final r = await db.from('promotions').select().eq('is_active', true).lte('starts_at', now).gte('ends_at', now).order('starts_at', ascending: false);
    return r.map(Promotion.fromJson).toList();
  }

  Future<List<HomeService>> homeServices() async {
    final r = await db.from('home_services').select().eq('is_active', true).order('sort', ascending: true);
    return r.map(HomeService.fromJson).toList();
  }

  Future<List<Merchant>> providersFor(String serviceId) async {
    final r = await db.from('merchant_services').select('merchants!inner(*)').eq('service_id', serviceId).eq('merchants.status', 'approved');
    return r.map((e) => Merchant.fromJson(e['merchants'] as Json)).toList();
  }

  Future<Map<String, dynamic>> settings() async {
    final r = await db.from('app_settings').select();
    return {for (final e in r) e['key'] as String: e['value']};
  }

  /// ترتيب الرئيسية من الإدارة (migration 0009). يرجّع [HomeSection.fallback] إذا الخادم قديم أو ما رجّع أقسام،
  /// ويتجاهل الأنواع اللي هذي النسخة ما تعرفها.
  Future<List<HomeSection>> homeLayout() async {
    try {
      final r = await db.rpc('home_layout') as List;
      final list = r.map((e) => HomeSection.fromJson(e as Json)).where((s) => s.type != HomeSectionType.unknown).toList();
      return list.isEmpty ? HomeSection.fallback : list;
    } on PostgrestException {
      return HomeSection.fallback;
    }
  }
}

// =====================================================================
// المستهلك: العناوين، المفضلة، الطلبات، الرحلات، المهام، الخدمات
// =====================================================================
class CustomerApi {
  const CustomerApi();

  // ---------- العناوين ----------
  Future<List<Address>> addresses() async {
    final r = await db.from('addresses').select().eq('user_id', _uid).order('is_default', ascending: false).order('created_at', ascending: true);
    return r.map(Address.fromJson).toList();
  }

  Future<Address> saveAddress({String? id, required String label, required String details, required String landmark, required double lat, required double lng, bool isDefault = false}) async {
    if (isDefault) await db.from('addresses').update({'is_default': false}).eq('user_id', _uid);
    final data = {'user_id': _uid, 'label': label, 'details': details, 'landmark': landmark, 'lat': lat, 'lng': lng, 'is_default': isDefault};
    final r = id == null
        ? await db.from('addresses').insert(data).select().single()
        : await db.from('addresses').update(data).eq('id', id).select().single();
    return Address.fromJson(r);
  }

  Future<void> deleteAddress(String id) => db.from('addresses').delete().eq('id', id);

  // ---------- المفضلة ----------
  Future<Set<String>> favoriteIds() async {
    final r = await db.from('favorites').select('merchant_id').eq('user_id', _uid);
    return r.map((e) => e['merchant_id'] as String).toSet();
  }

  Future<List<Merchant>> favoriteMerchants() async {
    final r = await db.from('favorites').select('merchants(*)').eq('user_id', _uid).order('created_at', ascending: false);
    return r.where((e) => e['merchants'] != null).map((e) => Merchant.fromJson(e['merchants'] as Json)).toList();
  }

  Future<void> setFavorite(String merchantId, bool fav) async {
    if (fav) {
      await db.from('favorites').upsert({'user_id': _uid, 'merchant_id': merchantId});
    } else {
      await db.from('favorites').delete().eq('user_id', _uid).eq('merchant_id', merchantId);
    }
  }

  // ---------- الطلبات ----------
  static const orderSelect = '*, order_items(*), merchants(name, logo_url, lat, lng)';

  Future<Order> placeOrder({
    required String merchantId,
    required String addressId,
    required List<Map<String, dynamic>> items,
    required String note,
    required String clientRef,
    String? promoCode,
    bool useWallet = false,
  }) async {
    final promo = promoCode?.trim() ?? '';
    final r = await db.rpc('place_order', params: {
      'p_merchant_id': merchantId,
      'p_address_id': addressId,
      'p_items': items,
      'p_note': note,
      'p_client_ref': clientRef,
      // المعاملان الجديدان ينرسلان فقط عند الحاجة حتى يبقى الطلب العادي شغّال على خادم قبل 0009
      if (promo.isNotEmpty) 'p_promo_code': promo,
      if (useWallet) 'p_use_wallet': true,
    });
    return order((r as Json)['id'] as String);
  }

  /// السعر كما يحسبه الخادم مع كود الخصم والرصيد (للعرض بالسلة)
  Future<CheckoutQuote> checkoutQuote({required String merchantId, required List<Map<String, dynamic>> items, String? promoCode, bool useWallet = false}) async {
    final r = await db.rpc('checkout_quote', params: {
      'p_merchant_id': merchantId,
      'p_items': items,
      'p_promo_code': promoCode,
      'p_use_wallet': useWallet,
    });
    return CheckoutQuote.fromJson(r as Json);
  }

  // ---------- المكافآت: رصيد، نقاط، دعوات ----------
  Future<Rewards> rewards() async => Rewards.fromJson(await db.rpc('my_rewards') as Json);

  Future<Rewards> redeemPoints() async => Rewards.fromJson(await db.rpc('redeem_points') as Json);

  Future<Rewards> applyReferralCode(String code) async => Rewards.fromJson(await db.rpc('apply_referral_code', params: {'p_code': code}) as Json);

  Future<Order> order(String id) async => Order.fromJson(await db.from('orders').select(orderSelect).eq('id', id).single());

  Future<List<Order>> myOrders({int limit = 50}) async {
    final r = await db.from('orders').select(orderSelect).eq('customer_id', _uid).order('created_at', ascending: false).limit(limit);
    return r.map(Order.fromJson).toList();
  }

  /// تحديثات الطلب لحظياً (حالة + موقع المندوب)
  Stream<Json?> watchOrderRow(String id) =>
      db.from('orders').stream(primaryKey: ['id']).eq('id', id).map((rows) => rows.isEmpty ? null : rows.first);

  Future<List<OrderStatusEvent>> orderHistory(String id) async {
    final r = await db.from('order_status_history').select().eq('order_id', id).order('created_at', ascending: true);
    return r.map(OrderStatusEvent.fromJson).toList();
  }

  Future<void> cancelOrder(String id) => db.rpc('customer_cancel_order', params: {'p_order_id': id});

  Future<void> rateOrder(String id, int rating, String comment) =>
      db.rpc('rate_order', params: {'p_order_id': id, 'p_rating': rating, 'p_comment': comment});

  // ---------- الرحلات ----------
  Future<({double distanceKm, int fare})> estimate(String service, double fLat, double fLng, double tLat, double tLng) async {
    final r = await db.rpc('estimate_fare', params: {'p_service': service, 'p_from_lat': fLat, 'p_from_lng': fLng, 'p_to_lat': tLat, 'p_to_lng': tLng}) as Json;
    return (distanceKm: (r['distance_km'] as num).toDouble(), fare: (r['fare'] as num).toInt());
  }

  Future<Ride> requestRide({required VehicleType vehicle, required String pickupText, required double pLat, required double pLng, required String dropoffText, required double dLat, required double dLng}) async {
    final r = await db.rpc('request_ride', params: {
      'p_vehicle': vehicle.name,
      'p_pickup_text': pickupText,
      'p_pickup_lat': pLat,
      'p_pickup_lng': pLng,
      'p_dropoff_text': dropoffText,
      'p_dropoff_lat': dLat,
      'p_dropoff_lng': dLng,
    });
    return Ride.fromJson(r as Json);
  }

  Future<List<Ride>> myRides() async {
    final r = await db.from('rides').select().eq('customer_id', _uid).order('created_at', ascending: false).limit(50);
    return r.map(Ride.fromJson).toList();
  }

  Stream<Ride?> watchRide(String id) =>
      db.from('rides').stream(primaryKey: ['id']).eq('id', id).map((rows) => rows.isEmpty ? null : Ride.fromJson(rows.first));

  Future<void> cancelRide(String id) => db.rpc('customer_cancel_ride', params: {'p_ride_id': id});

  Future<void> rateRide(String id, int rating, String comment) =>
      db.rpc('rate_ride', params: {'p_ride_id': id, 'p_rating': rating, 'p_comment': comment});

  /// الرحلة الشغّالة حالياً (إن وجدت) لعرضها بالرئيسية
  Future<Ride?> activeRide() async {
    final r = await db.from('rides').select().eq('customer_id', _uid).inFilter('status', ['requested', 'accepted', 'arrived', 'in_progress']).order('created_at', ascending: false).limit(1);
    return r.isEmpty ? null : Ride.fromJson(r.first);
  }

  /// أكثر وجهات الزبون تكراراً. قائمة فارغة إذا الخادم قبل 0009.
  Future<List<RideDestination>> rideDestinations({int limit = 4}) async {
    try {
      final r = await db.rpc('my_ride_destinations', params: {'p_limit': limit}) as List;
      return r.map((e) => RideDestination.fromJson(e as Json)).toList();
    } on PostgrestException {
      return const [];
    }
  }

  // ---------- المندوب وتوصيل الأغراض ----------
  Future<DeliveryTask> createErrand({
    required TaskKind kind,
    required String pickupText,
    required double pLat,
    required double pLng,
    required String dropoffText,
    required double dLat,
    required double dLng,
    required String itemType,
    required String description,
    required String recipientPhone,
    required String notes,
  }) async {
    final r = await db.rpc('create_errand', params: {
      'p_kind': kind.name,
      'p_pickup_text': pickupText,
      'p_pickup_lat': pLat,
      'p_pickup_lng': pLng,
      'p_dropoff_text': dropoffText,
      'p_dropoff_lat': dLat,
      'p_dropoff_lng': dLng,
      'p_item_type': itemType,
      'p_description': description,
      'p_recipient_phone': recipientPhone,
      'p_notes': notes,
    });
    return DeliveryTask.fromJson(r as Json);
  }

  Future<List<DeliveryTask>> myErrands() async {
    final r = await db.from('delivery_tasks').select().eq('customer_id', _uid).neq('kind', 'order').order('created_at', ascending: false).limit(50);
    return r.map(DeliveryTask.fromJson).toList();
  }

  Stream<DeliveryTask?> watchTask(String id) =>
      db.from('delivery_tasks').stream(primaryKey: ['id']).eq('id', id).map((rows) => rows.isEmpty ? null : DeliveryTask.fromJson(rows.first));

  Future<void> cancelErrand(String id) => db.rpc('customer_cancel_errand', params: {'p_task_id': id});

  // ---------- الخدمات المنزلية ----------
  Future<ServiceBooking> bookService({
    required String serviceId,
    required String providerId,
    required String addressText,
    required double lat,
    required double lng,
    required String description,
    required List<String> photoUrls,
    required DateTime preferredTime,
  }) async {
    final r = await db.rpc('book_service', params: {
      'p_service_id': serviceId,
      'p_provider_id': providerId,
      'p_address_text': addressText,
      'p_lat': lat,
      'p_lng': lng,
      'p_description': description,
      'p_photo_urls': photoUrls,
      'p_preferred_time': preferredTime.toUtc().toIso8601String(),
    });
    return ServiceBooking.fromJson(r as Json);
  }

  static const bookingSelect = '*, home_services(name), merchants(name, phone)';

  Future<List<ServiceBooking>> myBookings() async {
    final r = await db.from('service_bookings').select(bookingSelect).eq('customer_id', _uid).order('created_at', ascending: false).limit(50);
    return r.map(ServiceBooking.fromJson).toList();
  }

  Future<void> cancelBooking(String id) => db.rpc('customer_cancel_booking', params: {'p_booking_id': id});

  // ---------- الإشعارات ----------
  Stream<List<AppNotification>> watchNotifications() => db
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', _uid)
      .order('created_at')
      .limit(50)
      .map((rows) => rows.map(AppNotification.fromJson).toList());

  Future<void> markAllRead() => db.from('notifications').update({'is_read': true}).eq('user_id', _uid).eq('is_read', false);
}

// =====================================================================
// التاجر
// =====================================================================
class MerchantApi {
  const MerchantApi();

  Future<List<Merchant>> myMerchants() async {
    final r = await db.from('merchants').select().eq('owner_id', _uid).order('name', ascending: true);
    return r.map(Merchant.fromJson).toList();
  }

  Stream<List<Order>> watchOrders(String merchantId) => db
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('merchant_id', merchantId)
      .order('created_at')
      .limit(200)
      .map((rows) => rows.map(Order.fromJson).toList());

  Future<List<OrderItem>> orderItems(String orderId) async {
    final r = await db.from('order_items').select().eq('order_id', orderId);
    return r.map(OrderItem.fromJson).toList();
  }

  Future<void> setOrderStatus(String orderId, OrderStatus status, {String? reason}) =>
      db.rpc('merchant_set_order_status', params: {'p_order_id': orderId, 'p_status': orderStatusDb(status), 'p_reason': reason});

  Future<Map<String, dynamic>> stats(String merchantId) async =>
      (await db.rpc('merchant_stats', params: {'p_merchant_id': merchantId})) as Json;

  /// عمولة واصل على المحل: النسبة، مستحق الشهر، المتبقي، والدفعات
  Future<Map<String, dynamic>> commission(String merchantId) async =>
      (await db.rpc('merchant_commission_summary', params: {'p_merchant_id': merchantId})) as Json;

  Future<void> updateProfile(String merchantId, {String? description, String? phone, Map<String, DayHours>? hours, bool? accepting, int? prepMinutes, String? logoUrl, String? coverUrl}) =>
      db.rpc('merchant_update_profile', params: {
        'p_merchant_id': merchantId,
        'p_description': description,
        'p_phone': phone,
        'p_working_hours': hours?.map((k, v) => MapEntry(k, v.toJson())),
        'p_is_accepting': accepting,
        'p_prep_minutes': prepMinutes,
        'p_logo_url': logoUrl,
        'p_cover_url': coverUrl,
      });

  // ---------- المنتجات ----------
  Future<ProductCategory> addCategory(String merchantId, String name) async =>
      ProductCategory.fromJson(await db.from('product_categories').insert({'merchant_id': merchantId, 'name': name.trim()}).select().single());

  Future<void> deleteCategory(String id) => db.from('product_categories').delete().eq('id', id);

  Future<Product> saveProduct({
    String? id,
    required String merchantId,
    String? categoryId,
    required String name,
    required String description,
    required int price,
    required bool isAvailable,
    int? stock,
    String? imageUrl,
  }) async {
    final data = {
      'merchant_id': merchantId,
      'category_id': categoryId,
      'name': name.trim(),
      'description': description.trim(),
      'price': price,
      'is_available': isAvailable,
      'stock': stock,
    };
    final row = id == null
        ? await db.from('products').insert(data).select().single()
        : await db.from('products').update(data).eq('id', id).select().single();
    final pid = row['id'] as String;
    if (imageUrl != null) {
      await db.from('product_images').delete().eq('product_id', pid);
      await db.from('product_images').insert({'product_id': pid, 'url': imageUrl, 'sort': 0});
    }
    return Product.fromJson(await db.from('products').select('*, product_images(url, sort)').eq('id', pid).single());
  }

  Future<void> setAvailability(String productId, bool available) =>
      db.from('products').update({'is_available': available}).eq('id', productId);

  Future<void> deleteProduct(String id) => db.from('products').delete().eq('id', id);

  // ---------- الخدمات المنزلية (مقدّم الخدمة) ----------
  Stream<List<ServiceBooking>> watchBookings(String merchantId) => db
      .from('service_bookings')
      .stream(primaryKey: ['id'])
      .eq('provider_id', merchantId)
      .order('created_at')
      .map((rows) => rows.map(ServiceBooking.fromJson).toList());

  Future<void> updateBooking(String id, BookingStatus status, {String? note}) =>
      db.rpc('provider_update_booking', params: {'p_booking_id': id, 'p_status': bookingStatusDb(status), 'p_note': note});
}

// =====================================================================
// السائق / المندوب
// =====================================================================
class DriverApi {
  const DriverApi();

  Future<Driver?> me() async {
    final r = await db.from('drivers').select('*, vehicles(*)').eq('id', _uid).maybeSingle();
    return r == null ? null : Driver.fromJson(r);
  }

  Future<Driver> setAvailable(bool available, {double? lat, double? lng}) async =>
      Driver.fromJson(await db.rpc('driver_set_available', params: {'p_available': available, 'p_lat': lat, 'p_lng': lng}) as Json);

  Future<void> updateLocation(double lat, double lng) => db.rpc('driver_update_location', params: {'p_lat': lat, 'p_lng': lng});

  /// المهام: RLS ترجّع المتاحة لنوع مركبتي + مهامي
  Stream<List<DeliveryTask>> watchTasks() => db
      .from('delivery_tasks')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .limit(100)
      .map((rows) => rows.map(DeliveryTask.fromJson).toList());

  Stream<List<Ride>> watchRides() => db
      .from('rides')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .limit(100)
      .map((rows) => rows.map(Ride.fromJson).toList());

  Future<void> acceptTask(String id) => db.rpc('driver_accept_task', params: {'p_task_id': id});
  Future<void> releaseTask(String id) => db.rpc('driver_release_task', params: {'p_task_id': id});
  Future<void> updateTask(String id, TaskStatus s) => db.rpc('driver_update_task', params: {'p_task_id': id, 'p_status': taskStatusDb(s)});
  Future<void> acceptRide(String id) => db.rpc('driver_accept_ride', params: {'p_ride_id': id});
  Future<void> updateRide(String id, RideStatus s) => db.rpc('driver_update_ride', params: {'p_ride_id': id, 'p_status': rideStatusDb(s)});
}

// =====================================================================
// الإدارة
// =====================================================================
class AdminApi {
  const AdminApi();

  Future<Map<String, dynamic>> stats() async => (await db.rpc('admin_stats')) as Json;

  /// تقارير الرسوم البيانية (يحتاج migration 0006)
  Future<Map<String, dynamic>> reports({int days = 14}) async => (await db.rpc('admin_reports', params: {'p_days': days})) as Json;

  /// بيانات خريطة العمليات: سائقين بآخر موقع، طلبات جارية، محلات معتمدة، مناطق
  Future<({List<Driver> drivers, List<Order> activeOrders, List<Merchant> merchants, List<ServiceArea> areas})> opsMap() async {
    final r = await Future.wait([
      db.from('drivers').select('*, vehicles(*), users(full_name, phone)').not('last_lat', 'is', null),
      db.from('orders').select('*, merchants(name, logo_url, lat, lng)').not('status', 'in', '(delivered,cancelled)').limit(200),
      db.from('merchants').select().eq('status', 'approved'),
      db.from('service_areas').select(),
    ]);
    return (
      drivers: r[0].map(Driver.fromJson).toList(),
      activeOrders: r[1].map(Order.fromJson).toList(),
      merchants: r[2].map(Merchant.fromJson).toList(),
      areas: r[3].map(ServiceArea.fromJson).toList(),
    );
  }

  // ---------- المحلات ----------
  Future<List<Merchant>> merchants({String? status, String? categoryId, String? search}) async {
    var q = db.from('merchants').select();
    if (status != null) q = q.eq('status', status);
    if (categoryId != null) q = q.eq('category_id', categoryId);
    if (search != null && search.trim().isNotEmpty) q = q.ilike('name', '%${search.trim()}%');
    final r = await q.order('created_at', ascending: false);
    return r.map(Merchant.fromJson).toList();
  }

  Future<Merchant> saveMerchant(String? id, Json data) async {
    final r = id == null
        ? await db.from('merchants').insert(data).select().single()
        : await db.from('merchants').update(data).eq('id', id).select().single();
    return Merchant.fromJson(r);
  }

  /// يحذف المحل فقط إذا ما عنده طلبات/حجوزات؛ غير ذلك يرمي merchant_has_history (والحل: إيقاف).
  Future<void> deleteMerchant(String id) => db.rpc('admin_delete_merchant', params: {'p_merchant_id': id});

  // ---------- العمولة ----------
  Future<Map<String, dynamic>> commissionSummary({int days = 30}) async =>
      (await db.rpc('admin_commission_summary', params: {'p_days': days})) as Json;

  Future<void> addSettlement(String merchantId, int amount, {String note = ''}) =>
      db.rpc('admin_add_settlement', params: {'p_merchant_id': merchantId, 'p_amount': amount, 'p_note': note});

  Future<void> linkOwner(String merchantId, String? userId) =>
      db.rpc('admin_link_merchant_owner', params: {'p_merchant_id': merchantId, 'p_user_id': userId});

  Future<Set<String>> merchantServiceIds(String merchantId) async {
    final r = await db.from('merchant_services').select('service_id').eq('merchant_id', merchantId);
    return r.map((e) => e['service_id'] as String).toSet();
  }

  Future<void> setMerchantServices(String merchantId, Set<String> serviceIds) async {
    await db.from('merchant_services').delete().eq('merchant_id', merchantId);
    if (serviceIds.isNotEmpty) {
      await db.from('merchant_services').insert(serviceIds.map((s) => {'merchant_id': merchantId, 'service_id': s}).toList());
    }
  }

  // ---------- المستخدمون ----------
  Future<List<(AppUser, Set<AppRole>)>> users({String? search, int limit = 100}) async {
    var q = db.from('users').select('*, user_roles(role)');
    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      q = q.or('full_name.ilike.%$s%,phone.ilike.%$s%');
    }
    final r = await q.order('created_at', ascending: false).limit(limit);
    return r
        .map((j) => (
              AppUser.fromJson(j),
              ((j['user_roles'] as List?) ?? const []).map((e) => AppRole.values.byName(e['role'] as String)).toSet(),
            ))
        .toList();
  }

  Future<AppUser?> userByPhone(String phone07) async {
    final r = await db.from('users').select().eq('phone', phone07).maybeSingle();
    return r == null ? null : AppUser.fromJson(r);
  }

  Future<void> setUserActive(String userId, bool active) => db.from('users').update({'is_active': active}).eq('id', userId);

  Future<void> setRole(String userId, AppRole role, bool grant) =>
      db.rpc('admin_set_role', params: {'p_user_id': userId, 'p_role': role.name, 'p_grant': grant});

  // ---------- السائقون ----------
  Future<List<Driver>> drivers() async {
    final r = await db.from('drivers').select('*, vehicles(*), users(full_name, phone)').order('created_at', ascending: false);
    return r.map(Driver.fromJson).toList();
  }

  Future<void> upsertDriver({required String userId, required VehicleType vehicle, String? areaId, required String plate, required String model, required String color, required bool active}) =>
      db.rpc('admin_upsert_driver', params: {
        'p_user_id': userId,
        'p_vehicle': vehicle.name,
        'p_area_id': areaId,
        'p_plate': plate,
        'p_model': model,
        'p_color': color,
        'p_active': active,
      });

  // ---------- الطلبات بكل أنواعها ----------
  Stream<List<Order>> watchOrders() => db
      .from('orders')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .limit(300)
      .map((rows) => rows.map(Order.fromJson).toList());

  Future<List<Order>> orders({String? status, List<String>? statuses, String? categoryId, String? customerId, int limit = 200}) async {
    var q = db.from('orders').select('*, order_items(*), merchants!inner(name, logo_url, lat, lng, category_id)');
    if (status != null) q = q.eq('status', status);
    if (statuses != null) q = q.inFilter('status', statuses);
    if (customerId != null) q = q.eq('customer_id', customerId);
    if (categoryId != null) q = q.eq('merchants.category_id', categoryId);
    final r = await q.order('created_at', ascending: false).limit(limit);
    return r.map(Order.fromJson).toList();
  }

  Future<List<Ride>> rides({String? vehicle, String? status, List<String>? statuses}) async {
    var q = db.from('rides').select();
    if (vehicle != null) q = q.eq('vehicle', vehicle);
    if (status != null) q = q.eq('status', status);
    if (statuses != null) q = q.inFilter('status', statuses);
    final r = await q.order('created_at', ascending: false).limit(200);
    return r.map(Ride.fromJson).toList();
  }

  Future<List<DeliveryTask>> errands({String? status, List<String>? statuses}) async {
    var q = db.from('delivery_tasks').select().neq('kind', 'order');
    if (status != null) q = q.eq('status', status);
    if (statuses != null) q = q.inFilter('status', statuses);
    final r = await q.order('created_at', ascending: false).limit(200);
    return r.map(DeliveryTask.fromJson).toList();
  }

  Future<List<ServiceBooking>> bookings({String? status, List<String>? statuses}) async {
    var q = db.from('service_bookings').select(CustomerApi.bookingSelect);
    if (status != null) q = q.eq('status', status);
    if (statuses != null) q = q.inFilter('status', statuses);
    final r = await q.order('created_at', ascending: false).limit(200);
    return r.map(ServiceBooking.fromJson).toList();
  }

  Future<void> cancelOrder(String id, String reason) => db.rpc('admin_cancel_order', params: {'p_order_id': id, 'p_reason': reason});

  // ---------- المناطق ----------
  Future<void> saveArea(String? id, Json data) async {
    if (id == null) {
      await db.from('service_areas').insert(data);
    } else {
      await db.from('service_areas').update(data).eq('id', id);
    }
  }

  Future<void> deleteArea(String id) => db.from('service_areas').delete().eq('id', id);

  // ---------- العروض ----------
  Future<List<Promotion>> promotions() async {
    final r = await db.from('promotions').select().order('created_at', ascending: false);
    return r.map(Promotion.fromJson).toList();
  }

  Future<void> savePromotion(String? id, Json data) async {
    if (id == null) {
      await db.from('promotions').insert(data);
    } else {
      await db.from('promotions').update(data).eq('id', id);
    }
  }

  Future<void> deletePromotion(String id) => db.from('promotions').delete().eq('id', id);

  // ---------- الخدمات المنزلية والأقسام ----------
  Future<List<HomeService>> allHomeServices() async {
    final r = await db.from('home_services').select().order('sort', ascending: true);
    return r.map(HomeService.fromJson).toList();
  }

  Future<void> saveHomeService(String? id, String name, bool active) async {
    if (id == null) {
      final next = (await db.from('home_services').select('sort').order('sort', ascending: false).limit(1));
      final sort = next.isEmpty ? 1 : ((next.first['sort'] as num).toInt() + 1);
      await db.from('home_services').insert({'name': name.trim(), 'is_active': active, 'sort': sort});
    } else {
      await db.from('home_services').update({'name': name.trim(), 'is_active': active}).eq('id', id);
    }
  }

  Future<List<MerchantCategory>> allCategories() async {
    final r = await db.from('merchant_categories').select().order('sort', ascending: true);
    return r.map(MerchantCategory.fromJson).toList();
  }

  Future<void> setCategoryActive(String id, bool active) => db.from('merchant_categories').update({'is_active': active}).eq('id', id);

  // ---------- الإعدادات ----------
  Future<void> saveSetting(String key, Object value) =>
      db.from('app_settings').upsert({'key': key, 'value': value, 'updated_at': DateTime.now().toUtc().toIso8601String()});

  // ---------- الرئيسية (migration 0009) ----------
  Future<List<HomeSection>> homeSections() async {
    final r = await db.from('home_sections').select('*, home_items(*)').order('sort', ascending: true).order('created_at', ascending: true);
    return r.map(HomeSection.fromJson).toList();
  }

  Future<void> saveHomeSection(String? id, Json data) async {
    if (id == null) {
      await db.from('home_sections').insert(data);
    } else {
      await db.from('home_sections').update(data).eq('id', id);
    }
  }

  Future<void> deleteHomeSection(String id) => db.from('home_sections').delete().eq('id', id);

  /// يحفظ ترتيب الأقسام حسب تسلسل القائمة
  Future<void> reorderHomeSections(List<String> ids) async {
    await Future.wait([
      for (var i = 0; i < ids.length; i++) db.from('home_sections').update({'sort': (i + 1) * 10}).eq('id', ids[i]),
    ]);
  }

  Future<void> saveHomeItem(String? id, Json data) async {
    if (id == null) {
      await db.from('home_items').insert(data);
    } else {
      await db.from('home_items').update(data).eq('id', id);
    }
  }

  Future<void> deleteHomeItem(String id) => db.from('home_items').delete().eq('id', id);

  // ---------- أكواد الخصم ----------
  Future<List<PromoCode>> promoCodes() async {
    final r = await db.from('promo_codes').select().order('created_at', ascending: false);
    return r.map(PromoCode.fromJson).toList();
  }

  Future<void> savePromoCode(String? id, Json data) async {
    if (id == null) {
      await db.from('promo_codes').insert(data);
    } else {
      await db.from('promo_codes').update(data).eq('id', id);
    }
  }

  Future<void> deletePromoCode(String id) => db.from('promo_codes').delete().eq('id', id);

  // ---------- المحفظة والنمو ----------
  /// يضيف (موجب) أو يخصم (سالب) رصيد لزبون. يرجّع الرصيد الجديد.
  Future<int> walletAdjust(String userId, int amount, String note) async =>
      ((await db.rpc('admin_wallet_adjust', params: {'p_user_id': userId, 'p_amount': amount, 'p_note': note})) as num).toInt();

  Future<int> walletBalance(String userId) async {
    final r = await db.from('wallet_ledger').select('amount').eq('user_id', userId);
    return r.fold<int>(0, (a, e) => a + (e['amount'] as num).toInt());
  }

  Future<Map<String, dynamic>> growthStats() async => (await db.rpc('admin_growth_stats')) as Json;
}

// =====================================================================
// رفع الصور
// =====================================================================
class MediaApi {
  const MediaApi();

  /// يرفع صورة ويرجّع رابطها العام. [folder] مثل: `merchants/ID` أو `bookings/UID`
  Future<String> upload(String folder, Uint8List bytes, {String ext = 'jpg'}) async {
    final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.$ext';
    await db.storage.from('media').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg', upsert: true, cacheControl: '31536000'),
        );
    return db.storage.from('media').getPublicUrl(path);
  }
}

const catalogApi = CatalogApi();
const customerApi = CustomerApi();
const merchantApi = MerchantApi();
const driverApi = DriverApi();
const adminApi = AdminApi();
const mediaApi = MediaApi();
