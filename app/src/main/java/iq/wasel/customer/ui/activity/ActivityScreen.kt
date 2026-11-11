package iq.wasel.customer.ui.activity

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import iq.wasel.customer.AppViewModel
import iq.wasel.customer.Nav
import iq.wasel.customer.Route
import iq.wasel.customer.data.Order
import iq.wasel.customer.data.OrderStatus
import iq.wasel.customer.ui.common.HSpace
import iq.wasel.customer.ui.common.SectionHeader
import iq.wasel.customer.ui.common.StepBar
import iq.wasel.customer.ui.common.StoreBadge
import iq.wasel.customer.ui.common.VSpace
import iq.wasel.customer.ui.common.formatDateTime
import iq.wasel.customer.ui.common.iqd
import iq.wasel.customer.ui.common.iraqiMonths
import iq.wasel.customer.ui.common.toast
import iq.wasel.customer.ui.theme.Wc
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId

@Composable
fun ActivityScreen(vm: AppViewModel, nav: Nav) {
    val ctx = LocalContext.current
    val active = vm.orders.filter { it.status.isActive }
    val past = vm.orders.filter { !it.status.isActive }.sortedByDescending { it.createdAt }
    val byMonth = past.groupBy { YearMonth.from(Instant.ofEpochMilli(it.createdAt).atZone(ZoneId.systemDefault())) }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 120.dp)) {
        item {
            Column(
                Modifier
                    .statusBarsPadding()
                    .padding(start = 20.dp, end = 20.dp, top = 20.dp),
            ) {
                Text("نشاطي", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, color = Wc.Ink)
                Text("طلباتك الحالية والسابقة بمكان واحد", style = MaterialTheme.typography.bodyMedium, color = Wc.Muted)
            }
        }

        item { SectionHeader("الآن") }
        if (active.isEmpty()) {
            item {
                Text(
                    "ما عندك طلب شغّال هسه",
                    color = Wc.Muted,
                    modifier = Modifier
                        .padding(horizontal = 16.dp)
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(18.dp))
                        .background(Wc.Card)
                        .border(1.dp, Wc.Line, RoundedCornerShape(18.dp))
                        .padding(18.dp),
                )
            }
        } else {
            items(active, key = { "a_" + it.id }) { o ->
                ActiveOrderCard(o) { nav.go(Route.Tracking(o.id)) }
            }
        }

        byMonth.forEach { (ym, list) ->
            item(key = "m_$ym") {
                val spent = list.filter { it.status == OrderStatus.DELIVERED }.sumOf { it.total }
                SectionHeader("${iraqiMonths[ym.monthValue - 1]} ${ym.year}", "صرفت ${spent.iqd()}")
            }
            items(list, key = { "p_" + it.id }) { o ->
                PastOrderRow(o) {
                    val msg = vm.reorder(o)
                    if (msg != null) ctx.toast(msg)
                    nav.go(Route.Cart)
                }
            }
        }
    }
}

@Composable
private fun ActiveOrderCard(order: Order, onClick: () -> Unit) {
    Row(
        Modifier
            .padding(horizontal = 16.dp, vertical = 5.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(Wc.Ink)
            .clickable(onClick = onClick)
            .padding(18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StoreBadge(order.store, 44.dp)
        HSpace(12.dp)
        Column(Modifier.weight(1f)) {
            Text(order.store.name, style = MaterialTheme.typography.labelMedium, color = Color.White.copy(alpha = 0.7f))
            Text(order.status.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = Color.White)
            VSpace(10.dp)
            StepBar(order.status.step, onDark = true)
        }
        HSpace(10.dp)
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = "تتبع", tint = Wc.Saffron)
    }
}

@Composable
private fun PastOrderRow(order: Order, onReorder: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Row(
        Modifier
            .padding(horizontal = 16.dp, vertical = 5.dp)
            .fillMaxWidth()
            .clip(shape)
            .background(Wc.Card)
            .border(1.dp, Wc.Line, shape)
            .padding(14.dp),
    ) {
        StoreBadge(order.store, 44.dp)
        HSpace(12.dp)
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    order.store.name,
                    fontWeight = FontWeight.SemiBold,
                    color = Wc.Ink,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(order.total.iqd(), fontWeight = FontWeight.SemiBold, color = Wc.Ink)
            }
            Text(
                order.summary,
                style = MaterialTheme.typography.bodySmall,
                color = Wc.Muted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            VSpace(8.dp)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(formatDateTime(order.createdAt), style = MaterialTheme.typography.labelMedium, color = Wc.Muted)
                if (order.status == OrderStatus.CANCELLED) {
                    HSpace(8.dp)
                    Box(
                        Modifier
                            .clip(CircleShape)
                            .background(Wc.DangerSoft)
                            .padding(horizontal = 8.dp, vertical = 1.dp),
                    ) {
                        Text("ملغي", style = MaterialTheme.typography.labelSmall, color = Wc.Danger)
                    }
                }
                Spacer(Modifier.weight(1f))
                Row(
                    Modifier
                        .clip(CircleShape)
                        .clickable(onClick = onReorder)
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Rounded.Replay, contentDescription = null, tint = Wc.Primary, modifier = Modifier.size(16.dp))
                    HSpace(4.dp)
                    Text("اطلب مرة ثانية", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = Wc.Primary)
                }
            }
        }
    }
}
