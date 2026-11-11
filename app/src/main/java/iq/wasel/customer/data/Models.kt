package iq.wasel.customer.data

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import kotlin.math.max
import kotlin.math.roundToInt

data class GeoP(val lat: Double, val lng: Double)

data class Category(
    val id: String,
    val name: String,
    val icon: ImageVector,
    val tint: Color,
)

data class Store(
    val id: String,
    val name: String,
    val categoryId: String,
    val tagline: String,
    val rating: Double,
    val prepMinutes: Int,
    val distanceKm: Double,
    val deliveryFee: Int,
    val location: GeoP,
    val color: Color,
) {
    /** وقت الطريق بالدقائق (تقريبي حسب المسافة). */
    val travelMinutes: Int get() = max(3, (distanceKm * 4).roundToInt())

    /** وقت الوصول الكلي = التحضير + الطريق. */
    val etaMinutes: Int get() = prepMinutes + travelMinutes
}

data class Product(
    val id: String,
    val storeId: String,
    val name: String,
    val description: String,
    val price: Int,
    val section: String,
)

data class CartLine(val product: Product, val qty: Int)

data class Address(
    val id: String,
    val label: String,
    val details: String,
    val landmark: String,
    val location: GeoP,
)

data class Driver(
    val name: String,
    val vehicle: String,
    val isCar: Boolean,
    val rating: Double,
)

/**
 * حالات الطلب كما يحفظها الخادم. الواجهة تعرضها بأربع خطوات فقط (step).
 */
enum class OrderStatus {
    PENDING, ACCEPTED, PREPARING, READY, PICKED_UP, DELIVERED, CANCELLED;

    val isActive: Boolean get() = this != DELIVERED && this != CANCELLED

    /** 0 أُرسل · 1 يتجهّز · 2 بالطريق · 3 وصل */
    val step: Int
        get() = when (this) {
            PENDING -> 0
            ACCEPTED, PREPARING, READY -> 1
            PICKED_UP -> 2
            DELIVERED -> 3
            CANCELLED -> -1
        }

    val title: String
        get() = when (this) {
            PENDING -> "بانتظار موافقة المتجر"
            ACCEPTED -> "المتجر قبل طلبك"
            PREPARING -> "طلبك يتجهّز هسه"
            READY -> "الطلب جاهز والسائق واصل للمتجر"
            PICKED_UP -> "السائق بالطريق إليك"
            DELIVERED -> "وصل طلبك، بالعافية"
            CANCELLED -> "انلغى الطلب"
        }
}

data class OrderLine(
    val productId: String,
    val name: String,
    val price: Int,
    val qty: Int,
)

data class Order(
    val id: String,
    val store: Store,
    val lines: List<OrderLine>,
    val deliveryFee: Int,
    val address: Address,
    val createdAt: Long,
    val status: OrderStatus,
    val pin: String,
    val driver: Driver?,
    val note: String = "",
) {
    val subtotal: Int get() = lines.sumOf { it.price * it.qty }
    val total: Int get() = subtotal + deliveryFee
    val itemCount: Int get() = lines.sumOf { it.qty }
    val summary: String get() = lines.joinToString("، ") { "${it.qty}× ${it.name}" }
}
