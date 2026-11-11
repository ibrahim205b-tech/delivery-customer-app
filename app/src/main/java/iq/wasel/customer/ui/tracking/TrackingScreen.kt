package iq.wasel.customer.ui.tracking

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Call
import androidx.compose.material.icons.rounded.ChatBubble
import androidx.compose.material.icons.rounded.DirectionsCar
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.StarBorder
import androidx.compose.material.icons.rounded.TwoWheeler
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import iq.wasel.customer.AppViewModel
import iq.wasel.customer.Nav
import iq.wasel.customer.data.Driver
import iq.wasel.customer.data.Order
import iq.wasel.customer.data.OrderStatus
import iq.wasel.customer.ui.common.CircleIcon
import iq.wasel.customer.ui.common.HSpace
import iq.wasel.customer.ui.common.StepBar
import iq.wasel.customer.ui.common.StoreBadge
import iq.wasel.customer.ui.common.VSpace
import iq.wasel.customer.ui.common.iqd
import iq.wasel.customer.ui.common.toast
import iq.wasel.customer.ui.theme.Wc
import kotlin.math.ceil
import kotlin.math.max

@Composable
fun TrackingScreen(vm: AppViewModel, nav: Nav, orderId: String) {
    val order = vm.order(orderId)
    if (order == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("الطلب غير موجود") }
        return
    }
    val ctx = LocalContext.current
    val route = vm.routes[orderId]
    val onSecondLeg = order.status == OrderStatus.PICKED_UP || order.status == OrderStatus.DELIVERED
    val path = when {
        route == null -> listOf(order.store.location, order.address.location)
        onSecondLeg -> route.toCustomer
        else -> route.toStore + route.toCustomer
    }
    val driverPos = if (order.status.isActive || order.status == OrderStatus.DELIVERED) vm.driverPositions[orderId] else null

    Box(Modifier.fillMaxSize().background(Wc.Cream)) {
        TrackingMap(
            store = order.store.location,
            home = order.address.location,
            driver = driverPos,
            route = path,
            modifier = Modifier.fillMaxSize(),
        )

        Row(
            Modifier
                .statusBarsPadding()
                .padding(16.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.shadow(6.dp, CircleShape)) {
                CircleIcon(Icons.AutoMirrored.Rounded.ArrowBack, "رجوع", Color.White, Wc.Ink, onClick = nav::back)
            }
            Spacer(Modifier.weight(1f))
            Text(
                "طلب ${order.id}",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = Wc.Ink,
                modifier = Modifier
                    .shadow(6.dp, CircleShape)
                    .clip(CircleShape)
                    .background(Color.White)
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            )
        }

        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .shadow(24.dp, RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                .background(Wc.Card)
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 14.dp),
        ) {
            Box(
                Modifier
                    .align(Alignment.CenterHorizontally)
                    .width(40.dp)
                    .height(4.dp)
                    .clip(CircleShape)
                    .background(Wc.Line),
            )
            VSpace(14.dp)
            Text(order.status.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = Wc.Ink)
            Text(etaLine(order, vm.legProgress[orderId] ?: 0f), style = MaterialTheme.typography.bodyMedium, color = Wc.Muted)

            if (order.status != OrderStatus.CANCELLED) {
                VSpace(16.dp)
                StepBar(order.status.step, onDark = false)
                VSpace(6.dp)
                Row(Modifier.fillMaxWidth()) {
                    listOf("أُرسل", "يتجهّز", "بالطريق", "وصل").forEachIndexed { i, label ->
                        Text(
                            label,
                            style = MaterialTheme.typography.labelSmall,
                            color = if (i <= order.status.step) Wc.Ink else Wc.Muted,
                            fontWeight = if (i == order.status.step) FontWeight.Bold else FontWeight.Normal,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }

            if (order.status.isActive) {
                VSpace(16.dp)
                PinCard(order.pin)
            }

            order.driver?.let { driver ->
                if (order.status != OrderStatus.CANCELLED) {
                    VSpace(14.dp)
                    DriverRow(
                        driver,
                        onCall = { ctx.toast("بالنسخة الحقيقية الاتصال يمر برقم وسيط يحمي رقمك") },
                        onChat = { ctx.toast("المحادثة مع السائق جاية بالنسخة الجاية") },
                    )
                }
            }

            VSpace(14.dp)
            HorizontalDivider(color = Wc.Line)
            VSpace(12.dp)
            Row(verticalAlignment = Alignment.CenterVertically) {
                StoreBadge(order.store, 36.dp)
                HSpace(10.dp)
                Column(Modifier.weight(1f)) {
                    Text(order.store.name, fontWeight = FontWeight.SemiBold, color = Wc.Ink)
                    Text("${order.itemCount} منتجات · نقداً عند الاستلام", style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
                }
                Text(order.total.iqd(), fontWeight = FontWeight.Bold, color = Wc.Ink)
            }

            if (order.status == OrderStatus.PENDING || order.status == OrderStatus.ACCEPTED) {
                VSpace(6.dp)
                Text(
                    "إلغاء الطلب",
                    color = Wc.Danger,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .clip(RoundedCornerShape(10.dp))
                        .clickable { vm.cancel(orderId) }
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                )
            }

            if (order.status == OrderStatus.DELIVERED) {
                VSpace(12.dp)
                RateRow { stars -> ctx.toast("شكراً! قيّمت التجربة بـ $stars نجوم") }
            }
        }
    }
}

private fun etaLine(order: Order, legProgress: Float): String {
    val s = order.store
    return when (order.status) {
        OrderStatus.PENDING -> "عادةً المتجر يرد خلال دقيقة"
        OrderStatus.ACCEPTED, OrderStatus.PREPARING -> "يوصلك خلال ${s.etaMinutes} دقيقة تقريباً"
        OrderStatus.READY -> "يوصلك خلال ${s.travelMinutes + 2} دقيقة تقريباً"
        OrderStatus.PICKED_UP -> {
            val left = max(1, ceil((1f - legProgress) * s.travelMinutes).toInt())
            "باقي $left دقيقة تقريباً"
        }
        OrderStatus.DELIVERED -> "إذا اكو أي مشكلة بالطلب، احچي ويانا من حسابك"
        OrderStatus.CANCELLED -> "ما راح ينحسب عليك أي مبلغ"
    }
}

@Composable
private fun PinCard(pin: String) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Wc.SaffronSoft)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text("رمز التسليم", fontWeight = FontWeight.SemiBold, color = Wc.Ink)
            Text("عطِه للسائق بس لما يسلّمك الطلب بإيدك", style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
        }
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                pin.forEach { digit ->
                    Box(
                        Modifier
                            .size(width = 32.dp, height = 40.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color.White),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("$digit", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = Wc.Ink)
                    }
                }
            }
        }
    }
}

@Composable
private fun DriverRow(driver: Driver, onCall: () -> Unit, onChat: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(Wc.PrimarySoft),
            contentAlignment = Alignment.Center,
        ) {
            val initials = driver.name.split(" ").mapNotNull { it.firstOrNull() }.take(2).joinToString(" ")
            Text(initials, fontWeight = FontWeight.Bold, color = Wc.Primary)
        }
        HSpace(12.dp)
        Column(Modifier.weight(1f)) {
            Text(driver.name, fontWeight = FontWeight.SemiBold, color = Wc.Ink)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    if (driver.isCar) Icons.Rounded.DirectionsCar else Icons.Rounded.TwoWheeler,
                    contentDescription = null,
                    tint = Wc.Muted,
                    modifier = Modifier.size(15.dp),
                )
                HSpace(4.dp)
                Text("${driver.vehicle} · ", style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
                Icon(Icons.Rounded.Star, contentDescription = null, tint = Wc.Saffron, modifier = Modifier.size(14.dp))
                Text("${driver.rating}", style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
            }
        }
        CircleIcon(Icons.Rounded.ChatBubble, "محادثة", Wc.Cream, Wc.Ink, onClick = onChat)
        HSpace(8.dp)
        CircleIcon(Icons.Rounded.Call, "اتصال", Wc.Primary, Color.White, onClick = onCall)
    }
}

@Composable
private fun RateRow(onRate: (Int) -> Unit) {
    var rating by rememberSaveable { mutableIntStateOf(0) }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("شلون كانت التجربة؟", fontWeight = FontWeight.SemiBold, color = Wc.Ink)
        VSpace(6.dp)
        Row {
            (1..5).forEach { i ->
                Icon(
                    if (i <= rating) Icons.Rounded.Star else Icons.Rounded.StarBorder,
                    contentDescription = "$i",
                    tint = Wc.Saffron,
                    modifier = Modifier
                        .clip(CircleShape)
                        .clickable {
                            rating = i
                            onRate(i)
                        }
                        .padding(4.dp)
                        .size(32.dp),
                )
            }
        }
    }
}
