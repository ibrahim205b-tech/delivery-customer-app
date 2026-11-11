// نماذج البيانات المطابقة لجداول Supabase (supabase/migrations/0001_schema.sql).

typedef Json = Map<String, dynamic>;

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
double? _dn(dynamic v) => v == null ? null : (v as num).toDouble();
int _i(dynamic v) => v == null ? 0 : (v as num).toInt();
DateTime _t(dynamic v) => DateTime.parse(v as String).toLocal();
DateTime? _tn(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
String _s(dynamic v) => (v ?? '') as String;

enum AppRole { customer, merchant, driver, admin }

class AppUser {
  final String id;
  final String fullName;
  final String? phone;
  final bool isActive;
  final DateTime createdAt;

  const AppUser({required this.id, required this.fullName, this.phone, required this.isActive, required this.createdAt});

  factory AppUser.fromJson(Json j) => AppUser(
        id: j['id'] as String,
        fullName: _s(j['full_name']),
        phone: j['phone'] as String?,
        isActive: j['is_active'] as bool? ?? true,
        createdAt: _t(j['created_at']),
      );
}

enum CategoryKind { store, homeService, ride, courier, parcel }

CategoryKind _kind(String s) => switch (s) {
      'home_service' => CategoryKind.homeService,
      'ride' => CategoryKind.ride,
      'courier' => CategoryKind.courier,
      'parcel' => CategoryKind.parcel,
      _ => CategoryKind.store,
    };

class MerchantCategory {
  final String id;
  final String name;
  final CategoryKind kind;
  final String icon;
  final int sort;
  final bool isActive;

  const MerchantCategory({required this.id, required this.name, required this.kind, required this.icon, required this.sort, required this.isActive});

  factory MerchantCategory.fromJson(Json j) => MerchantCategory(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: _kind(j['kind'] as String),
        icon: j['icon'] as String,
        sort: _i(j['sort']),
        isActive: j['is_active'] as bool? ?? true,
      );
}

class ServiceArea {
  final String id;
  final String name;
  final String city;
  final double centerLat;
  final double centerLng;
  final double radiusKm;
  final bool isActive;

  const ServiceArea({required this.id, required this.name, required this.city, required this.centerLat, required this.centerLng, required this.radiusKm, required this.isActive});

  factory ServiceArea.fromJson(Json j) => ServiceArea(
        id: j['id'] as String,
        name: j['name'] as String,
        city: j['city'] as String,
        centerLat: _d(j['center_lat']),
        centerLng: _d(j['center_lng']),
        radiusKm: _d(j['radius_km']),
        isActive: j['is_active'] as bool? ?? true,
      );

  Json toJson() => {
        'name': name,
        'city': city,
        'center_lat': centerLat,
        'center_lng': centerLng,
        'radius_km': radiusKm,
        'is_active': isActive,
      };
}

enum MerchantStatus { pending, approved, suspended }

class DayHours {
  final String open;
  final String close;
  final bool closed;
  const DayHours({this.open = '09:00', this.close = '23:00', this.closed = false});

  factory DayHours.fromJson(Json? j) =>
      j == null ? const DayHours() : DayHours(open: _s(j['open']).isEmpty ? '09:00' : j['open'], close: _s(j['close']).isEmpty ? '23:00' : j['close'], closed: j['closed'] == true);
  Json toJson() => {'open': open, 'close': close, 'closed': closed};
  DayHours copyWith({String? open, String? close, bool? closed}) =>
      DayHours(open: open ?? this.open, close: close ?? this.close, closed: closed ?? this.closed);
}

class Merchant {
  final String id;
  final String? ownerId;
  final String categoryId;
  final String? areaId;
  final String name;
  final String description;
  final String addressText;
  final double lat;
  final double lng;
  final String phone;
  final String? coverUrl;
  final String? logoUrl;
  final int deliveryFee;
  final int minOrder;
  final int prepMinutes;
  final double deliveryRadiusKm;
  final Map<String, DayHours> workingHours; // "0".."6" (0 = الأحد)
  final MerchantStatus status;
  final bool isAcceptingOrders;
  final double ratingAvg;
  final int ratingCount;
  final int orderCount;
  final DateTime createdAt;

  const Merchant({
    required this.id,
    this.ownerId,
    required this.categoryId,
    this.areaId,
    required this.name,
    required this.description,
    required this.addressText,
    required this.lat,
    required this.lng,
    required this.phone,
    this.coverUrl,
    this.logoUrl,
    required this.deliveryFee,
    required this.minOrder,
    required this.prepMinutes,
    required this.deliveryRadiusKm,
    required this.workingHours,
    required this.status,
    required this.isAcceptingOrders,
    required this.ratingAvg,
    required this.ratingCount,
    required this.orderCount,
    required this.createdAt,
  });

  factory Merchant.fromJson(Json j) {
    final wh = <String, DayHours>{};
    final raw = j['working_hours'];
    if (raw is Map) {
      raw.forEach((k, v) => wh['$k'] = DayHours.fromJson((v as Map).cast<String, dynamic>()));
    }
    return Merchant(
      id: j['id'] as String,
      ownerId: j['owner_id'] as String?,
      categoryId: j['category_id'] as String,
      areaId: j['area_id'] as String?,
      name: j['name'] as String,
      description: _s(j['description']),
      addressText: _s(j['address_text']),
      lat: _d(j['lat']),
      lng: _d(j['lng']),
      phone: _s(j['phone']),
      coverUrl: j['cover_url'] as String?,
      logoUrl: j['logo_url'] as String?,
      deliveryFee: _i(j['delivery_fee']),
      minOrder: _i(j['min_order']),
      prepMinutes: _i(j['prep_minutes']),
      deliveryRadiusKm: _d(j['delivery_radius_km']),
      workingHours: wh,
      status: MerchantStatus.values.byName(j['status'] as String),
      isAcceptingOrders: j['is_accepting_orders'] as bool? ?? true,
      ratingAvg: _d(j['rating_avg']),
      ratingCount: _i(j['rating_count']),
      orderCount: _i(j['order_count']),
      createdAt: _t(j['created_at']),
    );
  }

  /// نفس منطق merchant_is_open بالخادم (للعرض فقط؛ الخادم هو الحكم النهائي).
  bool get isOpenNow {
    if (status != MerchantStatus.approved || !isAcceptingOrders) return false;
    final now = DateTime.now().toUtc().add(const Duration(hours: 3)); // توقيت بغداد
    final day = workingHours['${now.weekday % 7}'];
    if (day == null) return true;
    if (day.closed) return false;
    int mins(String hhmm) {
      final p = hhmm.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    final t = now.hour * 60 + now.minute;
    final o = mins(day.open), c = mins(day.close);
    if (c > o) return t >= o && t < c;
    return t >= o || t < c;
  }

  int etaMinutes(double distanceKm) => prepMinutes + (distanceKm * 4).ceil().clamp(5, 120);
}

class ProductCategory {
  final String id;
  final String merchantId;
  final String name;
  final int sort;
  const ProductCategory({required this.id, required this.merchantId, required this.name, required this.sort});
  factory ProductCategory.fromJson(Json j) =>
      ProductCategory(id: j['id'] as String, merchantId: j['merchant_id'] as String, name: j['name'] as String, sort: _i(j['sort']));
}

class Product {
  final String id;
  final String merchantId;
  final String? categoryId;
  final String name;
  final String description;
  final int price;
  final bool isAvailable;
  final int? stock;
  final int sort;
  final List<String> images;

  const Product({
    required this.id,
    required this.merchantId,
    this.categoryId,
    required this.name,
    required this.description,
    required this.price,
    required this.isAvailable,
    this.stock,
    required this.sort,
    this.images = const [],
  });

  factory Product.fromJson(Json j) {
    final imgs = (j['product_images'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final sorted = [...imgs]..sort((a, b) => _i(a['sort']).compareTo(_i(b['sort'])));
    return Product(
      id: j['id'] as String,
      merchantId: j['merchant_id'] as String,
      categoryId: j['category_id'] as String?,
      name: j['name'] as String,
      description: _s(j['description']),
      price: _i(j['price']),
      isAvailable: j['is_available'] as bool? ?? true,
      stock: j['stock'] == null ? null : _i(j['stock']),
      sort: _i(j['sort']),
      images: sorted.map((e) => e['url'] as String).toList(),
    );
  }

  String? get imageUrl => images.isEmpty ? null : images.first;
}

class Address {
  final String id;
  final String userId;
  final String label;
  final String details;
  final String landmark;
  final double lat;
  final double lng;
  final bool isDefault;

  const Address({required this.id, required this.userId, required this.label, required this.details, required this.landmark, required this.lat, required this.lng, required this.isDefault});

  factory Address.fromJson(Json j) => Address(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        label: _s(j['label']),
        details: _s(j['details']),
        landmark: _s(j['landmark']),
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        isDefault: j['is_default'] as bool? ?? false,
      );

  String get oneLine => [label, details].where((e) => e.isNotEmpty).join(' · ');
}

enum OrderStatus { placed, accepted, preparing, ready, pickedUp, onTheWay, delivered, cancelled }

OrderStatus orderStatusFrom(String s) => switch (s) {
      'picked_up' => OrderStatus.pickedUp,
      'on_the_way' => OrderStatus.onTheWay,
      _ => OrderStatus.values.byName(s),
    };

String orderStatusDb(OrderStatus s) => switch (s) {
      OrderStatus.pickedUp => 'picked_up',
      OrderStatus.onTheWay => 'on_the_way',
      _ => s.name,
    };

extension OrderStatusX on OrderStatus {
  String get label => switch (this) {
        OrderStatus.placed => 'تم إرسال الطلب',
        OrderStatus.accepted => 'المحل وافق على الطلب',
        OrderStatus.preparing => 'قيد التحضير',
        OrderStatus.ready => 'جاهز للاستلام',
        OrderStatus.pickedUp => 'المندوب استلم الطلب',
        OrderStatus.onTheWay => 'في الطريق',
        OrderStatus.delivered => 'تم التسليم',
        OrderStatus.cancelled => 'ملغي',
      };
  bool get isActive => this != OrderStatus.delivered && this != OrderStatus.cancelled;

  /// ترتيب المراحل المعروضة (الملغي خارجها)
  int get stepIndex => this == OrderStatus.cancelled ? -1 : index;
}

class OrderItem {
  final String id;
  final String? productId;
  final String name;
  final int unitPrice;
  final int qty;
  final String note;
  const OrderItem({required this.id, this.productId, required this.name, required this.unitPrice, required this.qty, required this.note});
  factory OrderItem.fromJson(Json j) => OrderItem(
        id: j['id'] as String,
        productId: j['product_id'] as String?,
        name: j['name'] as String,
        unitPrice: _i(j['unit_price']),
        qty: _i(j['qty']),
        note: _s(j['note']),
      );
}

class Order {
  final String id;
  final String code;
  final String customerId;
  final String merchantId;
  final String? driverId;
  final OrderStatus status;
  final String customerName;
  final String customerPhone;
  final String addressText;
  final double addressLat;
  final double addressLng;
  final String? driverName;
  final String? driverPhone;
  final String? driverVehicle;
  final double? driverLat;
  final double? driverLng;
  final int subtotal;
  final int deliveryFee;
  final int total;
  final String customerNote;
  final String? cancelReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<OrderItem> items;
  final String? merchantName;
  final String? merchantLogo;
  final double? merchantLat;
  final double? merchantLng;

  const Order({
    required this.id,
    required this.code,
    required this.customerId,
    required this.merchantId,
    this.driverId,
    required this.status,
    required this.customerName,
    required this.customerPhone,
    required this.addressText,
    required this.addressLat,
    required this.addressLng,
    this.driverName,
    this.driverPhone,
    this.driverVehicle,
    this.driverLat,
    this.driverLng,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.customerNote,
    this.cancelReason,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
    this.merchantName,
    this.merchantLogo,
    this.merchantLat,
    this.merchantLng,
  });

  factory Order.fromJson(Json j) {
    final m = j['merchants'] as Map<String, dynamic>?;
    return Order(
      id: j['id'] as String,
      code: j['code'] as String,
      customerId: j['customer_id'] as String,
      merchantId: j['merchant_id'] as String,
      driverId: j['driver_id'] as String?,
      status: orderStatusFrom(j['status'] as String),
      customerName: _s(j['customer_name']),
      customerPhone: _s(j['customer_phone']),
      addressText: _s(j['address_text']),
      addressLat: _d(j['address_lat']),
      addressLng: _d(j['address_lng']),
      driverName: j['driver_name'] as String?,
      driverPhone: j['driver_phone'] as String?,
      driverVehicle: j['driver_vehicle'] as String?,
      driverLat: _dn(j['driver_lat']),
      driverLng: _dn(j['driver_lng']),
      subtotal: _i(j['subtotal']),
      deliveryFee: _i(j['delivery_fee']),
      total: _i(j['total']),
      customerNote: _s(j['customer_note']),
      cancelReason: j['cancel_reason'] as String?,
      createdAt: _t(j['created_at']),
      updatedAt: _t(j['updated_at']),
      items: ((j['order_items'] as List?) ?? const []).map((e) => OrderItem.fromJson(e as Json)).toList(),
      merchantName: m?['name'] as String?,
      merchantLogo: m?['logo_url'] as String?,
      merchantLat: _dn(m?['lat']),
      merchantLng: _dn(m?['lng']),
    );
  }

  /// يدمج تحديث لحظي (صف orders فقط) مع البيانات المرتبطة الموجودة
  Order mergeRow(Json row) {
    final updated = Order.fromJson({
      ...row,
      'order_items': null,
      'merchants': null,
    });
    return Order(
      id: updated.id,
      code: updated.code,
      customerId: updated.customerId,
      merchantId: updated.merchantId,
      driverId: updated.driverId,
      status: updated.status,
      customerName: updated.customerName,
      customerPhone: updated.customerPhone,
      addressText: updated.addressText,
      addressLat: updated.addressLat,
      addressLng: updated.addressLng,
      driverName: updated.driverName,
      driverPhone: updated.driverPhone,
      driverVehicle: updated.driverVehicle,
      driverLat: updated.driverLat,
      driverLng: updated.driverLng,
      subtotal: updated.subtotal,
      deliveryFee: updated.deliveryFee,
      total: updated.total,
      customerNote: updated.customerNote,
      cancelReason: updated.cancelReason,
      createdAt: updated.createdAt,
      updatedAt: updated.updatedAt,
      items: items,
      merchantName: merchantName,
      merchantLogo: merchantLogo,
      merchantLat: merchantLat,
      merchantLng: merchantLng,
    );
  }

  String get itemsSummary => items.map((e) => '${e.qty}× ${e.name}').join('، ');
}

class OrderStatusEvent {
  final OrderStatus status;
  final DateTime at;
  final String? note;
  const OrderStatusEvent(this.status, this.at, this.note);
  factory OrderStatusEvent.fromJson(Json j) => OrderStatusEvent(orderStatusFrom(j['status'] as String), _t(j['created_at']), j['note'] as String?);
}

enum VehicleType { taxi, tuktuk, courier }

extension VehicleTypeX on VehicleType {
  String get label => switch (this) { VehicleType.taxi => 'تكسي', VehicleType.tuktuk => 'تكتك', VehicleType.courier => 'مندوب توصيل' };
}

class Driver {
  final String id;
  final VehicleType vehicleType;
  final String? areaId;
  final bool isActive;
  final bool isAvailable;
  final double? lastLat;
  final double? lastLng;
  final DateTime? lastSeenAt;
  final String? fullName;
  final String? phone;
  final String? plate;
  final String? model;
  final String? color;

  const Driver({
    required this.id,
    required this.vehicleType,
    this.areaId,
    required this.isActive,
    required this.isAvailable,
    this.lastLat,
    this.lastLng,
    this.lastSeenAt,
    this.fullName,
    this.phone,
    this.plate,
    this.model,
    this.color,
  });

  factory Driver.fromJson(Json j) {
    final u = j['users'] as Map<String, dynamic>?;
    final v = j['vehicles'];
    final vm = v is List ? (v.isEmpty ? null : v.first as Map<String, dynamic>) : v as Map<String, dynamic>?;
    return Driver(
      id: j['id'] as String,
      vehicleType: VehicleType.values.byName(j['vehicle_type'] as String),
      areaId: j['area_id'] as String?,
      isActive: j['is_active'] as bool? ?? true,
      isAvailable: j['is_available'] as bool? ?? false,
      lastLat: _dn(j['last_lat']),
      lastLng: _dn(j['last_lng']),
      lastSeenAt: _tn(j['last_seen_at']),
      fullName: u?['full_name'] as String?,
      phone: u?['phone'] as String?,
      plate: vm?['plate'] as String?,
      model: vm?['model'] as String?,
      color: vm?['color'] as String?,
    );
  }
}

enum TaskKind { order, courier, parcel }

enum TaskStatus { requested, assigned, pickedUp, onTheWay, delivered, cancelled }

TaskStatus taskStatusFrom(String s) => switch (s) {
      'picked_up' => TaskStatus.pickedUp,
      'on_the_way' => TaskStatus.onTheWay,
      _ => TaskStatus.values.byName(s),
    };

String taskStatusDb(TaskStatus s) => switch (s) {
      TaskStatus.pickedUp => 'picked_up',
      TaskStatus.onTheWay => 'on_the_way',
      _ => s.name,
    };

extension TaskStatusX on TaskStatus {
  String get label => switch (this) {
        TaskStatus.requested => 'بانتظار مندوب',
        TaskStatus.assigned => 'المندوب بالطريق للاستلام',
        TaskStatus.pickedUp => 'تم الاستلام',
        TaskStatus.onTheWay => 'في الطريق للتسليم',
        TaskStatus.delivered => 'تم التسليم',
        TaskStatus.cancelled => 'ملغي',
      };
  bool get isActive => this != TaskStatus.delivered && this != TaskStatus.cancelled;
}

extension TaskKindX on TaskKind {
  String get label => switch (this) { TaskKind.order => 'توصيل طلب', TaskKind.courier => 'مندوب', TaskKind.parcel => 'توصيل غرض' };
}

class DeliveryTask {
  final String id;
  final TaskKind kind;
  final String? orderId;
  final String customerId;
  final String? driverId;
  final TaskStatus status;
  final String pickupText;
  final double pickupLat;
  final double pickupLng;
  final String dropoffText;
  final double dropoffLat;
  final double dropoffLng;
  final String itemType;
  final String description;
  final String recipientPhone;
  final String notes;
  final String customerName;
  final String customerPhone;
  final String? driverName;
  final String? driverPhone;
  final double? driverLat;
  final double? driverLng;
  final double? distanceKm;
  final int fee;
  final DateTime createdAt;

  const DeliveryTask({
    required this.id,
    required this.kind,
    this.orderId,
    required this.customerId,
    this.driverId,
    required this.status,
    required this.pickupText,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffText,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.itemType,
    required this.description,
    required this.recipientPhone,
    required this.notes,
    required this.customerName,
    required this.customerPhone,
    this.driverName,
    this.driverPhone,
    this.driverLat,
    this.driverLng,
    this.distanceKm,
    required this.fee,
    required this.createdAt,
  });

  factory DeliveryTask.fromJson(Json j) => DeliveryTask(
        id: j['id'] as String,
        kind: TaskKind.values.byName(j['kind'] as String),
        orderId: j['order_id'] as String?,
        customerId: j['customer_id'] as String,
        driverId: j['driver_id'] as String?,
        status: taskStatusFrom(j['status'] as String),
        pickupText: _s(j['pickup_text']),
        pickupLat: _d(j['pickup_lat']),
        pickupLng: _d(j['pickup_lng']),
        dropoffText: _s(j['dropoff_text']),
        dropoffLat: _d(j['dropoff_lat']),
        dropoffLng: _d(j['dropoff_lng']),
        itemType: _s(j['item_type']),
        description: _s(j['description']),
        recipientPhone: _s(j['recipient_phone']),
        notes: _s(j['notes']),
        customerName: _s(j['customer_name']),
        customerPhone: _s(j['customer_phone']),
        driverName: j['driver_name'] as String?,
        driverPhone: j['driver_phone'] as String?,
        driverLat: _dn(j['driver_lat']),
        driverLng: _dn(j['driver_lng']),
        distanceKm: _dn(j['distance_km']),
        fee: _i(j['fee']),
        createdAt: _t(j['created_at']),
      );
}

enum RideStatus { requested, accepted, arrived, inProgress, completed, cancelled }

RideStatus rideStatusFrom(String s) => s == 'in_progress' ? RideStatus.inProgress : RideStatus.values.byName(s);
String rideStatusDb(RideStatus s) => s == RideStatus.inProgress ? 'in_progress' : s.name;

extension RideStatusX on RideStatus {
  String get label => switch (this) {
        RideStatus.requested => 'ندوّر لك على سائق',
        RideStatus.accepted => 'السائق جاي إليك',
        RideStatus.arrived => 'السائق وصل',
        RideStatus.inProgress => 'الرحلة بدأت',
        RideStatus.completed => 'وصلت بالسلامة',
        RideStatus.cancelled => 'ملغية',
      };
  bool get isActive => this != RideStatus.completed && this != RideStatus.cancelled;
}

class Ride {
  final String id;
  final String customerId;
  final String? driverId;
  final VehicleType vehicle;
  final RideStatus status;
  final String pickupText;
  final double pickupLat;
  final double pickupLng;
  final String dropoffText;
  final double dropoffLat;
  final double dropoffLng;
  final double distanceKm;
  final int fare;
  final String customerName;
  final String customerPhone;
  final String? driverName;
  final String? driverPhone;
  final String? driverVehicle;
  final double? driverLat;
  final double? driverLng;
  final DateTime createdAt;
  final DateTime? completedAt;

  const Ride({
    required this.id,
    required this.customerId,
    this.driverId,
    required this.vehicle,
    required this.status,
    required this.pickupText,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffText,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.distanceKm,
    required this.fare,
    required this.customerName,
    required this.customerPhone,
    this.driverName,
    this.driverPhone,
    this.driverVehicle,
    this.driverLat,
    this.driverLng,
    required this.createdAt,
    this.completedAt,
  });

  factory Ride.fromJson(Json j) => Ride(
        id: j['id'] as String,
        customerId: j['customer_id'] as String,
        driverId: j['driver_id'] as String?,
        vehicle: VehicleType.values.byName(j['vehicle'] as String),
        status: rideStatusFrom(j['status'] as String),
        pickupText: _s(j['pickup_text']),
        pickupLat: _d(j['pickup_lat']),
        pickupLng: _d(j['pickup_lng']),
        dropoffText: _s(j['dropoff_text']),
        dropoffLat: _d(j['dropoff_lat']),
        dropoffLng: _d(j['dropoff_lng']),
        distanceKm: _d(j['distance_km']),
        fare: _i(j['fare']),
        customerName: _s(j['customer_name']),
        customerPhone: _s(j['customer_phone']),
        driverName: j['driver_name'] as String?,
        driverPhone: j['driver_phone'] as String?,
        driverVehicle: j['driver_vehicle'] as String?,
        driverLat: _dn(j['driver_lat']),
        driverLng: _dn(j['driver_lng']),
        createdAt: _t(j['created_at']),
        completedAt: _tn(j['completed_at']),
      );
}

class HomeService {
  final String id;
  final String name;
  final String icon;
  final int sort;
  final bool isActive;
  const HomeService({required this.id, required this.name, required this.icon, required this.sort, required this.isActive});
  factory HomeService.fromJson(Json j) =>
      HomeService(id: j['id'] as String, name: j['name'] as String, icon: _s(j['icon']), sort: _i(j['sort']), isActive: j['is_active'] as bool? ?? true);
}

enum BookingStatus { requested, accepted, rejected, inProgress, completed, cancelled }

BookingStatus bookingStatusFrom(String s) => s == 'in_progress' ? BookingStatus.inProgress : BookingStatus.values.byName(s);
String bookingStatusDb(BookingStatus s) => s == BookingStatus.inProgress ? 'in_progress' : s.name;

extension BookingStatusX on BookingStatus {
  String get label => switch (this) {
        BookingStatus.requested => 'بانتظار رد مقدّم الخدمة',
        BookingStatus.accepted => 'مقبول',
        BookingStatus.rejected => 'مرفوض',
        BookingStatus.inProgress => 'قيد التنفيذ',
        BookingStatus.completed => 'مكتمل',
        BookingStatus.cancelled => 'ملغي',
      };
  bool get isActive => this == BookingStatus.requested || this == BookingStatus.accepted || this == BookingStatus.inProgress;
}

class ServiceBooking {
  final String id;
  final String customerId;
  final String serviceId;
  final String providerId;
  final BookingStatus status;
  final String addressText;
  final double lat;
  final double lng;
  final String description;
  final List<String> photoUrls;
  final DateTime preferredTime;
  final String customerName;
  final String customerPhone;
  final String? providerNote;
  final DateTime createdAt;
  final String? serviceName;
  final String? providerName;
  final String? providerPhone;

  const ServiceBooking({
    required this.id,
    required this.customerId,
    required this.serviceId,
    required this.providerId,
    required this.status,
    required this.addressText,
    required this.lat,
    required this.lng,
    required this.description,
    required this.photoUrls,
    required this.preferredTime,
    required this.customerName,
    required this.customerPhone,
    this.providerNote,
    required this.createdAt,
    this.serviceName,
    this.providerName,
    this.providerPhone,
  });

  factory ServiceBooking.fromJson(Json j) => ServiceBooking(
        id: j['id'] as String,
        customerId: j['customer_id'] as String,
        serviceId: j['service_id'] as String,
        providerId: j['provider_id'] as String,
        status: bookingStatusFrom(j['status'] as String),
        addressText: _s(j['address_text']),
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        description: _s(j['description']),
        photoUrls: ((j['photo_urls'] as List?) ?? const []).cast<String>(),
        preferredTime: _t(j['preferred_time']),
        customerName: _s(j['customer_name']),
        customerPhone: _s(j['customer_phone']),
        providerNote: j['provider_note'] as String?,
        createdAt: _t(j['created_at']),
        serviceName: (j['home_services'] as Map?)?['name'] as String?,
        providerName: (j['merchants'] as Map?)?['name'] as String?,
        providerPhone: (j['merchants'] as Map?)?['phone'] as String?,
      );
}

class Promotion {
  final String id;
  final String title;
  final String description;
  final String? imageUrl;
  final String? merchantId;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isActive;

  const Promotion({required this.id, required this.title, required this.description, this.imageUrl, this.merchantId, required this.startsAt, required this.endsAt, required this.isActive});

  factory Promotion.fromJson(Json j) => Promotion(
        id: j['id'] as String,
        title: j['title'] as String,
        description: _s(j['description']),
        imageUrl: j['image_url'] as String?,
        merchantId: j['merchant_id'] as String?,
        startsAt: _t(j['starts_at']),
        endsAt: _t(j['ends_at']),
        isActive: j['is_active'] as bool? ?? true,
      );
}

class AppNotification {
  final int id;
  final String title;
  final String body;
  final Json data;
  final bool isRead;
  final DateTime createdAt;
  const AppNotification({required this.id, required this.title, required this.body, required this.data, required this.isRead, required this.createdAt});
  factory AppNotification.fromJson(Json j) => AppNotification(
        id: _i(j['id']),
        title: j['title'] as String,
        body: _s(j['body']),
        data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        isRead: j['is_read'] as bool? ?? false,
        createdAt: _t(j['created_at']),
      );
}
