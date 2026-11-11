package iq.wasel.customer.ui.cart

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.LocationOn
import androidx.compose.material.icons.rounded.Payments
import androidx.compose.material.icons.rounded.ShoppingBag
import androidx.compose.material.icons.rounded.AccountBalanceWallet
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import iq.wasel.customer.AppViewModel
import iq.wasel.customer.Nav
import iq.wasel.customer.Route
import iq.wasel.customer.ui.common.EmptyState
import iq.wasel.customer.ui.common.HSpace
import iq.wasel.customer.ui.common.Panel
import iq.wasel.customer.ui.common.QtyStepper
import iq.wasel.customer.ui.common.StoreBadge
import iq.wasel.customer.ui.common.TopBar
import iq.wasel.customer.ui.common.VSpace
import iq.wasel.customer.ui.common.iqd
import iq.wasel.customer.ui.theme.Wc

@Composable
fun CartScreen(vm: AppViewModel, nav: Nav) {
    val store = vm.cartStore
    var note by rememberSaveable { mutableStateOf("") }

    Column(
        Modifier
            .fillMaxSize()
            .background(Wc.Cream),
    ) {
        TopBar("سلتك", onBack = nav::back)

        if (store == null) {
            EmptyState(Icons.Rounded.ShoppingBag, "سلتك فاضية", "ضيف شي من أي متجر ويطلع هنا")
            return@Column
        }

        LazyColumn(
            Modifier.weight(1f),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Panel {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        StoreBadge(store, 42.dp)
                        HSpace(12.dp)
                        Column {
                            Text(store.name, fontWeight = FontWeight.SemiBold, color = Wc.Ink)
                            Text("يتجهّز خلال ${store.prepMinutes} دقيقة تقريباً", style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
                        }
                    }
                    VSpace(12.dp)
                    HorizontalDivider(color = Wc.Line)
                    vm.cartLines.forEach { line ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .padding(top = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(line.product.name, fontWeight = FontWeight.Medium, color = Wc.Ink)
                                Text((line.product.price * line.qty).iqd(), style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
                            }
                            QtyStepper(line.qty, { vm.add(line.product) }, { vm.remove(line.product) })
                        }
                    }
                    Text(
                        "+ ضيف أغراض ثانية",
                        color = Wc.Primary,
                        fontWeight = FontWeight.SemiBold,
                        style = MaterialTheme.typography.labelLarge,
                        modifier = Modifier
                            .padding(top = 12.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .clickable { nav.back() }
                            .padding(vertical = 6.dp),
                    )
                }
            }

            item {
                val addr = vm.selectedAddress
                Panel {
                    Text("التوصيل إلى", style = MaterialTheme.typography.labelMedium, color = Wc.Muted)
                    VSpace(8.dp)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            Modifier
                                .size(40.dp)
                                .clip(CircleShape)
                                .background(Wc.PrimarySoft),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Rounded.LocationOn, contentDescription = null, tint = Wc.Primary)
                        }
                        HSpace(12.dp)
                        Column(Modifier.weight(1f)) {
                            Text(addr.label, fontWeight = FontWeight.SemiBold, color = Wc.Ink)
                            Text(addr.details, style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
                            Text("علامة دالة: ${addr.landmark}", style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
                        }
                        Text(
                            "تغيير",
                            color = Wc.Primary,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .clickable { nav.go(Route.Addresses) }
                                .padding(8.dp),
                        )
                    }
                }
            }

            item {
                Panel {
                    Text("طريقة الدفع", style = MaterialTheme.typography.labelMedium, color = Wc.Muted)
                    VSpace(8.dp)
                    PaymentOption(Icons.Rounded.Payments, "نقداً عند الاستلام", selected = true, badge = null)
                    VSpace(8.dp)
                    PaymentOption(Icons.Rounded.AccountBalanceWallet, "محفظة إلكترونية", selected = false, badge = "قريباً")
                }
            }

            item {
                Panel {
                    Text("ملاحظة للمتجر", style = MaterialTheme.typography.labelMedium, color = Wc.Muted)
                    VSpace(8.dp)
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(Wc.Cream)
                            .padding(12.dp),
                    ) {
                        if (note.isEmpty()) {
                            Text("مثلاً: بدون بصل، أو اتصل قبل لا توصل", color = Wc.Muted.copy(alpha = 0.7f))
                        }
                        BasicTextField(
                            value = note,
                            onValueChange = { note = it },
                            textStyle = MaterialTheme.typography.bodyMedium.copy(color = Wc.Ink),
                            cursorBrush = SolidColor(Wc.Primary),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }

            item {
                Panel {
                    SummaryRow("المنتجات", vm.cartSubtotal.iqd())
                    SummaryRow("التوصيل", store.deliveryFee.iqd())
                    VSpace(6.dp)
                    HorizontalDivider(color = Wc.Line)
                    VSpace(6.dp)
                    SummaryRow("المجموع", (vm.cartSubtotal + store.deliveryFee).iqd(), bold = true)
                }
            }
        }

        Surface(color = Wc.Card, shadowElevation = 16.dp) {
            Button(
                onClick = {
                    vm.placeOrder(note.trim())?.let { id -> nav.replace(Route.Tracking(id)) }
                },
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Wc.Ink, contentColor = Color.White),
                contentPadding = PaddingValues(horizontal = 20.dp),
                modifier = Modifier
                    .navigationBarsPadding()
                    .padding(16.dp)
                    .fillMaxWidth()
                    .height(58.dp),
            ) {
                Text("أكّد الطلب", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                Text((vm.cartSubtotal + store.deliveryFee).iqd(), style = MaterialTheme.typography.titleMedium, color = Wc.Saffron)
            }
        }
    }
}

@Composable
private fun PaymentOption(icon: ImageVector, title: String, selected: Boolean, badge: String?) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .border(1.5.dp, if (selected) Wc.Primary else Wc.Line, shape)
            .background(if (selected) Wc.PrimarySoft.copy(alpha = 0.5f) else Color.Transparent)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = if (selected) Wc.Primary else Wc.Muted)
        HSpace(10.dp)
        Text(
            title,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (selected) Wc.Ink else Wc.Muted,
            modifier = Modifier.weight(1f),
        )
        if (badge != null) {
            Text(
                badge,
                style = MaterialTheme.typography.labelSmall,
                color = Wc.Ink,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(Wc.SaffronSoft)
                    .padding(horizontal = 8.dp, vertical = 2.dp),
            )
        }
    }
}

@Composable
private fun SummaryRow(label: String, value: String, bold: Boolean = false) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp),
    ) {
        Text(
            label,
            color = if (bold) Wc.Ink else Wc.Muted,
            fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal,
            modifier = Modifier.weight(1f),
        )
        Text(value, color = Wc.Ink, fontWeight = if (bold) FontWeight.Bold else FontWeight.Medium)
    }
}
