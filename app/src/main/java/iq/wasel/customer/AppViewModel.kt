package iq.wasel.customer

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import iq.wasel.customer.data.Address
import iq.wasel.customer.data.CartLine
import iq.wasel.customer.data.DemoData
import iq.wasel.customer.data.GeoP
import iq.wasel.customer.data.Order
import iq.wasel.customer.data.OrderLine
import iq.wasel.customer.data.OrderStatus
import iq.wasel.customer.data.Product
import iq.wasel.customer.data.Store
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.hypot
import kotlin.random.Random

/** مسار السائق: من مكانه للمتجر، ثم من المتجر للزبون. */
data class DeliveryRoute(val toStore: List<GeoP>, val toCustomer: List<GeoP>)

class AppViewModel : ViewModel() {

    // ---------------- السلة ----------------

    /** productId -> الكمية. السلة دائماً من متجر واحد. */
    var cart by mutableStateOf<Map<String, Int>>(emptyMap())
        private set

    /** منتج ينتظر تأكيد "نبدأ سلة جديدة؟" لأنه من متجر ثاني. */
    var pendingSwitch by mutableStateOf<Product?>(null)
        private set

    val cartLines: List<CartLine>
        get() = cart.mapNotNull { (id, qty) -> DemoData.product(id)?.let { CartLine(it, qty) } }

    val cartStore: Store?
        get() = cart.keys.firstOrNull()?.let { DemoData.product(it) }?.let { DemoData.store(it.storeId) }

    val cartCount: Int get() = cart.values.sum()
    val cartSubtotal: Int get() = cartLines.sumOf { it.product.price * it.qty }

    fun qtyOf(productId: String): Int = cart[productId] ?: 0

    fun add(product: Product) {
        val current = cartStore
        if (current != null && current.id != product.storeId) {
            pendingSwitch = product
            return
        }
        cart = cart + (product.id to qtyOf(product.id) + 1)
    }

    fun remove(product: Product) {
        val q = qtyOf(product.id)
        cart = if (q <= 1) cart - product.id else cart + (product.id to q - 1)
    }

    fun confirmSwitch() {
        val p = pendingSwitch ?: return
        cart = mapOf(p.id to 1)
        pendingSwitch = null
    }

    fun dismissSwitch() {
        pendingSwitch = null
    }

    // ---------------- العناوين ----------------

    val addresses: List<Address> = DemoData.addresses
    var selectedAddressId by mutableStateOf(DemoData.addresses.first().id)
    val selectedAddress: Address get() = addresses.first { it.id == selectedAddressId }

    // ---------------- المفضلة ----------------

    var favoriteStores by mutableStateOf(setOf("s3", "s5"))
        private set
    var favoriteProducts by mutableStateOf(setOf("p604"))
        private set

    fun toggleFavStore(id: String) {
        favoriteStores = if (id in favoriteStores) favoriteStores - id else favoriteStores + id
    }

    fun toggleFavProduct(id: String) {
        favoriteProducts = if (id in favoriteProducts) favoriteProducts - id else favoriteProducts + id
    }

    // ---------------- الإشعارات ----------------

    var notifOffers by mutableStateOf(false)
    var notifNewStores by mutableStateOf(true)
    var quietHours by mutableStateOf(true)

    // ---------------- الطلبات ----------------

    val orders = mutableStateListOf<Order>().apply { addAll(DemoData.pastOrders) }
    val routes = mutableStateMapOf<String, DeliveryRoute>()
    val driverPositions = mutableStateMapOf<String, GeoP>()

    /** تقدّم السائق على المرحلة الحالية من المسار (0..1). */
    val legProgress = mutableStateMapOf<String, Float>()

    fun order(id: String): Order? = orders.firstOrNull { it.id == id }

    /** ينشئ الطلب ويرجع رقمه. بالتطبيق الحقيقي هذا POST /orders مع Idempotency-Key. */
    fun placeOrder(note: String): String? {
        val store = cartStore ?: return null
        val id = "W-" + Random.nextInt(10500, 99999)
        val order = Order(
            id = id,
            store = store,
            lines = cartLines.map { OrderLine(it.product.id, it.product.name, it.product.price, it.qty) },
            deliveryFee = store.deliveryFee,
            address = selectedAddress,
            createdAt = System.currentTimeMillis(),
            status = OrderStatus.PENDING,
            pin = Random.nextInt(1000, 9999).toString(),
            driver = null,
            note = note,
        )
        orders.add(0, order)
        cart = emptyMap()
        simulate(id)
        return id
    }

    fun cancel(orderId: String) {
        val o = order(orderId) ?: return
        if (o.status == OrderStatus.PENDING || o.status == OrderStatus.ACCEPTED) {
            update(orderId) { it.copy(status = OrderStatus.CANCELLED) }
            driverPositions.remove(orderId)
        }
    }

    /**
     * "اطلب مرة ثانية": يرجّع المنتجات للسلة بالأسعار الحالية.
     * يرجع رسالة تنبيه إذا منتج اختفى أو سعره تغيّر.
     */
    fun reorder(order: Order): String? {
        val missing = mutableListOf<String>()
        var priceChanged = false
        val newCart = mutableMapOf<String, Int>()
        order.lines.forEach { l ->
            val p = DemoData.product(l.productId)
            if (p == null) {
                missing += l.name
            } else {
                newCart[p.id] = l.qty
                if (p.price != l.price) priceChanged = true
            }
        }
        if (newCart.isEmpty()) return "هاي المنتجات ما متوفرة حالياً"
        cart = newCart
        return when {
            missing.isNotEmpty() -> "بعض المنتجات ما متوفرة: " + missing.joinToString("، ")
            priceChanged -> "انتبه: بعض الأسعار تغيّرت من آخر مرة"
            else -> null
        }
    }

    private fun update(id: String, change: (Order) -> Order) {
        val i = orders.indexOfFirst { it.id == id }
        if (i >= 0) orders[i] = change(orders[i])
    }

    private fun isCancelled(id: String) = order(id)?.status == OrderStatus.CANCELLED

    /**
     * محاكاة لما يصير بالخادم: المتجر يقبل، يجهّز، السائق يجي ويستلم ويوصل.
     * بالتطبيق الحقيقي هاي التحديثات توصل عن طريق WebSocket وإشعارات FCM.
     */
    private fun simulate(id: String) = viewModelScope.launch {
        val o = order(id) ?: return@launch
        val store = o.store.location
        val home = o.address.location
        val driverStart = GeoP(store.lat + 0.0055, store.lng - 0.0075)
        val route = DeliveryRoute(streetRoute(driverStart, store), streetRoute(store, home))
        routes[id] = route

        delay(3500)
        if (isCancelled(id)) return@launch
        update(id) { it.copy(status = OrderStatus.ACCEPTED) }

        delay(3000)
        if (isCancelled(id)) return@launch
        update(id) { it.copy(status = OrderStatus.PREPARING, driver = DemoData.drivers.random()) }

        moveAlong(id, route.toStore, durationMs = 12_000)
        if (isCancelled(id)) return@launch
        update(id) { it.copy(status = OrderStatus.READY) }

        delay(3000)
        update(id) { it.copy(status = OrderStatus.PICKED_UP) }
        moveAlong(id, route.toCustomer, durationMs = 22_000)

        update(id) { it.copy(status = OrderStatus.DELIVERED) }
    }

    private suspend fun moveAlong(id: String, path: List<GeoP>, durationMs: Long) {
        val steps = (durationMs / 400).toInt()
        for (s in 0..steps) {
            val t = s / steps.toFloat()
            legProgress[id] = t
            driverPositions[id] = pointAlong(path, t)
            delay(400)
        }
    }

    /** مسار على شكل شوارع (زوايا قائمة) بدل خط مستقيم. */
    private fun streetRoute(a: GeoP, b: GeoP): List<GeoP> {
        val midLng = (a.lng + b.lng) / 2
        return listOf(a, GeoP(a.lat, midLng), GeoP(b.lat, midLng), b)
    }

    private fun pointAlong(path: List<GeoP>, t: Float): GeoP {
        if (path.size < 2) return path.first()
        val segments = path.zipWithNext()
        val lengths = segments.map { (a, b) -> hypot(b.lat - a.lat, b.lng - a.lng) }
        var d = lengths.sum() * t.coerceIn(0f, 1f)
        segments.forEachIndexed { i, (a, b) ->
            if (d <= lengths[i] || i == segments.lastIndex) {
                val f = if (lengths[i] == 0.0) 0.0 else (d / lengths[i]).coerceIn(0.0, 1.0)
                return GeoP(a.lat + (b.lat - a.lat) * f, a.lng + (b.lng - a.lng) * f)
            }
            d -= lengths[i]
        }
        return path.last()
    }
}
