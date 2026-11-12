// اختبار تكامل حقيقي ضد Supabase (محلي أو سحابي) بنفس كود التطبيقات.
// يتخطّى تلقائياً إذا متغيرات البيئة غير موجودة.
//
//   WASEL_IT_URL=http://localhost:54321 WASEL_IT_ANON=... WASEL_IT_SERVICE=... flutter test test/integration_test.dart
//
// كل مستخدم له عميل Supabase مستقل (جلسة مستقلة)، ونبدّل بينهم كما لو كانوا أجهزة مختلفة.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:wasel_core/wasel_core.dart';

final env = Platform.environment;
final url = env['WASEL_IT_URL'];
final anon = env['WASEL_IT_ANON'];
final service = env['WASEL_IT_SERVICE'];

SupabaseClient newClient() => SupabaseClient(url!, anon!, authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));

/// ينتظر أول قيمة من الستريم تحقق الشرط (للتحديثات اللحظية)
Future<T> waitFor<T>(Stream<T> s, bool Function(T) test, {Duration timeout = const Duration(seconds: 20), String what = ''}) {
  final c = Completer<T>();
  late StreamSubscription<T> sub;
  sub = s.listen((v) {
    if (!c.isCompleted && test(v)) {
      c.complete(v);
      sub.cancel();
    }
  }, onError: (e) {
    if (!c.isCompleted) c.completeError(e);
  });
  return c.future.timeout(timeout, onTimeout: () {
    sub.cancel();
    throw TimeoutException('ما وصل التحديث اللحظي: $what');
  });
}

void main() {
  final skip = (url == null || anon == null || service == null) ? 'WASEL_IT_* env vars not set' : null;

  // أرقام فريدة لكل تشغيل حتى يتكرر الاختبار بدون تعارض
  final run = 1000000 + Random().nextInt(8999999);
  String phone(int i) => '07${(run * 10 + i).toString().padLeft(9, '0').substring(0, 9)}';

  late SupabaseClient adminC, ownerC, custC, courierC, taxiC, provC, svc;
  final ids = <String, String>{};

  Future<void> as(SupabaseClient c, Future<void> Function() body) async {
    useClientForTesting(c);
    await body();
  }

  Future<String> signUp(SupabaseClient c, String name, String ph) async {
    final r = await c.auth.signUp(email: phoneToAuthEmail(ph), password: 'secret123', data: {'full_name': name, 'phone': ph});
    return r.user!.id;
  }

  setUpAll(() async {
    if (skip != null) return;
    svc = SupabaseClient(url!, service!);
    adminC = newClient();
    ownerC = newClient();
    custC = newClient();
    courierC = newClient();
    taxiC = newClient();
    provC = newClient();
  });

  tearDownAll(() async {
    if (skip != null) return;
    for (final c in [adminC, ownerC, custC, courierC, taxiC, provC]) {
      await c.dispose();
    }
  });

  test('1) التسجيل برقم الهاتف عبر AuthController', () async {
    useClientForTesting(custC);
    final auth = AuthController();
    await auth.signUp(fullName: 'زبون التكامل', phone: phone(3), password: 'secret123');
    expect(auth.isSignedIn, isTrue);
    expect(auth.profile?.phone, phone(3));
    expect(auth.hasRole(AppRole.customer), isTrue);
    ids['cust'] = auth.userId!;

    // تسجيل خروج ودخول من جديد بنفس الرقم بصيغة دولية
    await auth.signOut();
    expect(auth.isSignedIn, isFalse);
    await auth.signIn(phone: '+964 ${phone(3).substring(1)}', password: 'secret123');
    expect(auth.isSignedIn, isTrue);
    auth.dispose();

    ids['admin'] = await signUp(adminC, 'مدير التكامل', phone(1));
    ids['owner'] = await signUp(ownerC, 'تاجر التكامل', phone(2));
    ids['courier'] = await signUp(courierC, 'مندوب التكامل', phone(4));
    ids['taxi'] = await signUp(taxiC, 'سائق التكامل', phone(5));
    ids['prov'] = await signUp(provC, 'فني التكامل', phone(6));
    // أول مدير يُمنح يدوياً (بمفتاح الخدمة، كما بالـ README)
    await svc.from('user_roles').insert({'user_id': ids['admin'], 'role': 'admin'});
  }, skip: skip);

  test('2) الإدارة تضيف منطقة ومحل وتربط التاجر والسواق', () async {
    await as(custC, () async {
      await expectLater(adminApi.stats(), throwsA(predicate((e) => friendlyError(e!).contains('صلاحية'))));
    });
    await as(adminC, () async {
      await adminApi.saveArea(null, {'name': 'منطقة $run', 'city': 'بغداد', 'center_lat': 33.30, 'center_lng': 44.43, 'radius_km': 8});
      final area = (await catalogApi.areas()).firstWhere((a) => a.name == 'منطقة $run');
      ids['area'] = area.id;
      final owner = await adminApi.userByPhone(phone(2));
      expect(owner?.id, ids['owner']);
      final m = await adminApi.saveMerchant(null, {
        'name': 'مطعم $run', 'category_id': 'restaurants', 'area_id': area.id, 'lat': 33.305, 'lng': 44.432,
        'address_text': 'شارع التجربة', 'phone': phone(2), 'delivery_fee': 1500, 'min_order': 0, 'status': 'pending',
      });
      ids['rest'] = m.id;
      await adminApi.linkOwner(m.id, ids['owner']);
      final p = await adminApi.saveMerchant(null, {'name': 'فني $run', 'category_id': 'home_services', 'lat': 33.30, 'lng': 44.43, 'status': 'approved'});
      ids['provider'] = p.id;
      await adminApi.linkOwner(p.id, ids['prov']);
      final plumbing = (await adminApi.allHomeServices()).firstWhere((s) => s.name == 'سباكة');
      ids['plumbing'] = plumbing.id;
      await adminApi.setMerchantServices(p.id, {plumbing.id});
      await adminApi.upsertDriver(userId: ids['courier']!, vehicle: VehicleType.courier, areaId: area.id, plate: '', model: 'دراجة', color: 'أحمر', active: true);
      await adminApi.upsertDriver(userId: ids['taxi']!, vehicle: VehicleType.taxi, areaId: area.id, plate: '12345', model: 'كيا', color: 'أبيض', active: true);
      final drivers = await adminApi.drivers();
      expect(drivers.where((d) => d.id == ids['taxi']).single.model, 'كيا');
    });
  }, skip: skip);

  test('3) التاجر يضيف منتج مع صورة حقيقية (Storage)', () async {
    await as(ownerC, () async {
      final mine = await merchantApi.myMerchants();
      expect(mine.map((m) => m.id), contains(ids['rest']));
      final cat = await merchantApi.addCategory(ids['rest']!, 'المشويات');
      // صورة PNG صغيرة 1x1
      final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 15, 4, 0, 9, 251, 3, 253, 227, 85, 242, 156, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]);
      final imgUrl = await mediaApi.upload('merchants/${ids['rest']}', png, ext: 'png');
      final res = await HttpClient().getUrl(Uri.parse(imgUrl)).then((r) => r.close());
      expect(res.statusCode, 200, reason: 'الصورة المرفوعة لازم تنفتح برابطها العام');
      final p = await merchantApi.saveProduct(merchantId: ids['rest']!, categoryId: cat.id, name: 'تكة $run', description: 'سيخين', price: 7000, isAvailable: true, imageUrl: imgUrl);
      ids['p1'] = p.id;
      expect(p.imageUrl, imgUrl);
      final p2 = await merchantApi.saveProduct(merchantId: ids['rest']!, name: 'شوربة $run', description: '', price: 1500, isAvailable: true, stock: 5);
      ids['p2'] = p2.id;
      // رفع صورة لمحل غيره ممنوع
      await expectLater(mediaApi.upload('merchants/${ids['provider']}', png, ext: 'png'), throwsA(anything));
    });
  }, skip: skip);

  test('4) المحل يظهر للمستهلك بعد اعتماد الإدارة فقط', () async {
    await as(custC, () async {
      expect((await catalogApi.merchants(categoryId: 'restaurants')).any((m) => m.id == ids['rest']), isFalse);
    });
    await as(adminC, () => adminApi.saveMerchant(ids['rest'], {'status': 'approved'}));
    await as(custC, () async {
      final list = await catalogApi.merchants(categoryId: 'restaurants', areaId: ids['area']);
      expect(list.map((m) => m.id), contains(ids['rest']));
      final products = await catalogApi.products(ids['rest']!);
      expect(products.length, 2);
      final s = await catalogApi.search('تكة $run');
      expect(s.products.single.$1.id, ids['p1']);
      expect(s.products.single.$2.name, 'مطعم $run');
    });
  }, skip: skip);

  test('5) دورة الطلب الكاملة مع التحديثات اللحظية لكل الأطراف', () async {
    // التاجر يستمع لطلبات محله لحظياً
    useClientForTesting(ownerC);
    final merchantStream = merchantApi.watchOrders(ids['rest']!).asBroadcastStream();
    // أول قيمة تصل بعد تأكيد الاشتراك اللحظي (القائمة الحالية: فارغة)
    expect(await merchantStream.first.timeout(const Duration(seconds: 20)), isEmpty);
    final newOrder = waitFor(merchantStream, (l) => l.isNotEmpty, what: 'طلب جديد عند التاجر');

    late Order order;
    await as(custC, () async {
      final a = await customerApi.saveAddress(label: 'البيت', details: 'زقاق 1', landmark: 'الجامع', lat: 33.302, lng: 44.437, isDefault: true);
      final ref = newClientRef();
      order = await customerApi.placeOrder(
        merchantId: ids['rest']!, addressId: a.id, clientRef: ref, note: 'بدون بصل',
        items: [{'product_id': ids['p1'], 'qty': 2, 'note': 'حار'}, {'product_id': ids['p2'], 'qty': 1}],
      );
      expect(order.total, 2 * 7000 + 1500 + 1500);
      expect(order.items.length, 2);
      expect(order.merchantName, 'مطعم $run');
      // نفس المرجع = نفس الطلب
      final again = await customerApi.placeOrder(merchantId: ids['rest']!, addressId: a.id, items: [], note: '', clientRef: ref);
      expect(again.id, order.id);
    });

    final seen = await newOrder;
    expect(seen.first.id, order.id, reason: 'الطلب وصل للمحل لحظياً');
    expect(seen.first.customerPhone, phone(3));

    // الزبون يستمع لحالة طلبه
    useClientForTesting(custC);
    final custStream = customerApi.watchOrderRow(order.id).asBroadcastStream();
    expect((await custStream.first.timeout(const Duration(seconds: 20)))?['status'], 'placed');
    final accepted = waitFor(custStream, (r) => r?['status'] == 'accepted', what: 'قبول الطلب عند الزبون');

    await as(ownerC, () => merchantApi.setOrderStatus(order.id, OrderStatus.accepted));
    await accepted;

    // المندوب متاح ويستمع للمهام
    useClientForTesting(courierC);
    final me = await driverApi.setAvailable(true, lat: 33.306, lng: 44.430);
    expect(me.isAvailable, isTrue);
    final taskStream = driverApi.watchTasks().asBroadcastStream();
    await taskStream.first.timeout(const Duration(seconds: 20));
    final taskArrived = waitFor(taskStream, (l) => l.any((t) => t.orderId == order.id), what: 'مهمة جديدة عند المندوب');

    await as(ownerC, () async {
      await merchantApi.setOrderStatus(order.id, OrderStatus.preparing);
      await merchantApi.setOrderStatus(order.id, OrderStatus.ready);
      final stats = await merchantApi.stats(ids['rest']!);
      expect(stats['active'], 1);
    });

    final tasks = await taskArrived;
    final task = tasks.firstWhere((t) => t.orderId == order.id);

    final driverAssigned = waitFor(custStream, (r) => r?['driver_name'] == 'مندوب التكامل', what: 'اسم المندوب عند الزبون');
    final moved = waitFor(custStream, (r) => r?['driver_lat'] == 33.3045, what: 'موقع المندوب عند الزبون');
    final delivered = waitFor(custStream, (r) => r?['status'] == 'delivered', what: 'التسليم عند الزبون');
    await as(courierC, () async {
      await driverApi.acceptTask(task.id);
      await driverApi.updateLocation(33.3045, 44.4335);
      await driverApi.updateTask(task.id, TaskStatus.pickedUp);
      await driverApi.updateTask(task.id, TaskStatus.onTheWay);
    });
    await driverAssigned;
    await moved;
    await as(courierC, () => driverApi.updateTask(task.id, TaskStatus.delivered));
    await delivered;

    await as(custC, () async {
      final h = await customerApi.orderHistory(order.id);
      expect(h.map((e) => e.status), [
        OrderStatus.placed, OrderStatus.accepted, OrderStatus.preparing, OrderStatus.ready,
        OrderStatus.pickedUp, OrderStatus.onTheWay, OrderStatus.delivered,
      ]);
      await customerApi.rateOrder(order.id, 5, 'ممتاز');
      final mine = await customerApi.myOrders();
      expect(mine.first.status, OrderStatus.delivered);
    });
  }, skip: skip);

  test('6) رحلة تكسي مع تحديثات لحظية', () async {
    late Ride ride;
    useClientForTesting(taxiC);
    await driverApi.setAvailable(true, lat: 33.301, lng: 44.431);
    final rideStream = driverApi.watchRides().asBroadcastStream();
    await rideStream.first.timeout(const Duration(seconds: 20));
    final arrived = waitFor(rideStream, (l) => l.any((r) => r.status == RideStatus.requested), what: 'طلب رحلة عند السائق');

    await as(custC, () async {
      final est = await customerApi.estimate('taxi', 33.30, 44.43, 33.32, 44.40);
      expect(est.fare, greaterThan(0));
      ride = await customerApi.requestRide(vehicle: VehicleType.taxi, pickupText: 'البيت', pLat: 33.30, pLng: 44.43, dropoffText: 'السعدون', dLat: 33.32, dLng: 44.40);
      expect(ride.fare, est.fare);
    });
    await arrived;

    useClientForTesting(custC);
    final watch = customerApi.watchRide(ride.id).asBroadcastStream();
    expect((await watch.first.timeout(const Duration(seconds: 20)))?.status, RideStatus.requested);
    final done = waitFor(watch, (r) => r?.status == RideStatus.completed, what: 'اكتمال الرحلة عند الزبون');
    await as(taxiC, () async {
      await driverApi.acceptRide(ride.id);
      await driverApi.updateRide(ride.id, RideStatus.arrived);
      await driverApi.updateRide(ride.id, RideStatus.inProgress);
      await driverApi.updateRide(ride.id, RideStatus.completed);
    });
    final r = await done;
    expect(r!.driverVehicle, contains('كيا'));
  }, skip: skip);

  test('7) توصيل غرض بالمندوب', () async {
    late DeliveryTask t;
    await as(custC, () async {
      t = await customerApi.createErrand(kind: TaskKind.parcel, pickupText: 'البيت', pLat: 33.30, pLng: 44.43, dropoffText: 'بيت أهلي', dLat: 33.31, dLng: 44.42,
          itemType: 'أوراق', description: 'ظرف', recipientPhone: '07711111111', notes: '');
      expect(t.fee, greaterThan(0));
    });
    await as(courierC, () async {
      await driverApi.acceptTask(t.id);
      for (final s in [TaskStatus.pickedUp, TaskStatus.onTheWay, TaskStatus.delivered]) {
        await driverApi.updateTask(t.id, s);
      }
    });
    await as(custC, () async {
      final mine = await customerApi.myErrands();
      expect(mine.firstWhere((e) => e.id == t.id).status, TaskStatus.delivered);
    });
  }, skip: skip);

  test('8) حجز خدمة منزلية مع صورة', () async {
    late ServiceBooking b;
    await as(custC, () async {
      final providers = await catalogApi.providersFor(ids['plumbing']!);
      expect(providers.map((m) => m.id), contains(ids['provider']));
      final photo = await mediaApi.upload('bookings/${ids['cust']}', Uint8List.fromList(List.filled(64, 1)));
      b = await customerApi.bookService(serviceId: ids['plumbing']!, providerId: ids['provider']!, addressText: 'البيت', lat: 33.30, lng: 44.43,
          description: 'تسريب مي', photoUrls: [photo], preferredTime: DateTime.now().add(const Duration(days: 1)));
    });
    await as(ownerC, () async {
      // تاجر ثاني ما يشوف الحجز
      final rows = await db.from('service_bookings').select().eq('id', b.id);
      expect(rows, isEmpty);
    });
    await as(provC, () async {
      final list = await merchantApi.watchBookings(ids['provider']!).first;
      expect(list.single.description, 'تسريب مي');
      await merchantApi.updateBooking(b.id, BookingStatus.accepted, note: 'باچر 10 الصبح');
      await merchantApi.updateBooking(b.id, BookingStatus.inProgress);
      await merchantApi.updateBooking(b.id, BookingStatus.completed);
    });
    await as(custC, () async {
      final mine = await customerApi.myBookings();
      final x = mine.firstWhere((e) => e.id == b.id);
      expect(x.status, BookingStatus.completed);
      expect(x.serviceName, 'سباكة');
      expect(x.providerNote, 'باچر 10 الصبح');
    });
  }, skip: skip);

  test('9) الإشعارات والإحصائيات والصلاحيات', () async {
    await as(custC, () async {
      final n = await customerApi.watchNotifications().first;
      expect(n.where((x) => x.data['type'] == 'order').length, greaterThanOrEqualTo(6));
      await customerApi.markAllRead();
      // المستهلك ما يگدر يعدّل طلب مباشرة
      final before = await customerApi.myOrders();
      await db.from('orders').update({'total': 1}).eq('id', before.first.id);
      expect((await customerApi.order(before.first.id)).total, isNot(1));
    });
    await as(adminC, () async {
      final s = await adminApi.stats();
      expect(s['orders_delivered'], greaterThanOrEqualTo(1));
      final orders = await adminApi.orders(categoryId: 'restaurants');
      expect(orders.any((o) => o.merchantName == 'مطعم $run'), isTrue);
      final users = await adminApi.users(search: phone(3));
      expect(users.single.$2, contains(AppRole.customer));
      // تعطيل حساب ثم التأكد إنه ما يگدر يطلب
      await adminApi.setUserActive(ids['cust']!, false);
    });
    await as(custC, () async {
      await expectLater(
        customerApi.requestRide(vehicle: VehicleType.taxi, pickupText: 'a', pLat: 33.3, pLng: 44.43, dropoffText: 'b', dLat: 33.32, dLng: 44.40),
        throwsA(predicate((e) => friendlyError(e!).contains('موقوف'))),
      );
    });
    await as(adminC, () => adminApi.setUserActive(ids['cust']!, true));
  }, skip: skip);

  test('10) الدعم داخل التطبيق: رسالة، تنبيه لحظي للإدارة، ورد لحظي للمستخدم', () async {
    // الإدارة تراقب صندوق الدعم قبل ما توصل الرسالة
    useClientForTesting(adminC);
    final adminInbox = supportApi.watchAllThreads();
    final adminSees = waitFor<List<SupportThread>>(adminInbox, (l) => l.any((t) => t.userId == ids['cust'] && t.unreadForAdmin >= 1), what: 'رسالة الدعم عند الإدارة');

    await as(custC, () async {
      final m = await supportApi.send(SupportApp.customer, 'وين طلبي؟', orderCode: 'W-TEST');
      expect(m.fromAdmin, isFalse);
      expect(m.orderCode, 'W-TEST');
    });
    final threads = await adminSees;
    final th = threads.firstWhere((t) => t.userId == ids['cust']);
    expect(th.userName, isNotEmpty);
    expect(th.app, SupportApp.customer);

    // المستخدم يراقب محادثته ويستلم الرد لحظياً
    useClientForTesting(custC);
    final custThread = waitFor<SupportThread?>(supportApi.watchMyThread(SupportApp.customer), (t) => (t?.unreadForUser ?? 0) >= 1, what: 'رد الدعم عند المستخدم');
    final custMsgs = waitFor<List<SupportMessage>>(supportApi.watchMessages(th.id), (l) => l.any((m) => m.fromAdmin), what: 'رسالة الرد بالمحادثة');

    await as(adminC, () async {
      await supportApi.reply(th.id, 'طلبك بالطريق');
      await supportApi.markRead(th.id);
    });
    expect((await custThread)!.lastMessage, 'طلبك بالطريق');
    expect((await custMsgs).last.body, 'طلبك بالطريق');

    // التاجر ما يشوف محادثة الزبون، ولا يگدر يرد كإدارة
    await as(ownerC, () async {
      final r = await db.from('support_messages').select().eq('thread_id', th.id);
      expect(r, isEmpty);
      await expectLater(supportApi.reply(th.id, 'x'), throwsA(predicate((e) => friendlyError(e!).contains('صلاحية'))));
    });

    // أرقام التواصل من الإعدادات
    await as(custC, () async {
      final c = await supportApi.contacts();
      expect(c, isA<SupportContacts>());
    });
  }, skip: skip);

  test('11) العمولة الفعلية وحذف المحل الآمن', () async {
    // الإدارة تفعّل عمولة عامة 10%
    await as(adminC, () => db.from('app_settings').update({'value': {'enabled': true, 'percent': 10}}).eq('key', 'commission'));
    final rest = ids['rest']!;
    await as(adminC, () async {
      final s = await adminApi.commissionSummary(days: 30);
      expect(s['merchants'], isA<List>());
      // محل عنده طلبات: الحذف مرفوض برسالة واضحة
      await expectLater(adminApi.deleteMerchant(rest), throwsA(predicate((e) => friendlyError(e!).contains('طلبات سابقة'))));
      // نسبة خاصة للمحل
      await adminApi.saveMerchant(rest, {'commission_percent': 7.5});
    });
    await as(ownerC, () async {
      final c = await merchantApi.commission(rest);
      expect((c['percent'] as num).toDouble(), 7.5);
      expect(c['custom'], isTrue);
    });
    await as(adminC, () async {
      await adminApi.saveMerchant(rest, {'commission_percent': null});
      await db.from('app_settings').update({'value': {'enabled': false, 'percent': 0}}).eq('key', 'commission');
    });
  }, skip: skip);
}
