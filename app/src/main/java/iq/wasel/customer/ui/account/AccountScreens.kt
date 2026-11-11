package iq.wasel.customer.ui.account

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.LocationOn
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.SupportAgent
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import iq.wasel.customer.AppViewModel
import iq.wasel.customer.Nav
import iq.wasel.customer.Route
import iq.wasel.customer.data.DemoData
import iq.wasel.customer.data.OrderStatus
import iq.wasel.customer.ui.common.EmptyState
import iq.wasel.customer.ui.common.HSpace
import iq.wasel.customer.ui.common.Panel
import iq.wasel.customer.ui.common.StoreBadge
import iq.wasel.customer.ui.common.StoreRow
import iq.wasel.customer.ui.common.TopBar
import iq.wasel.customer.ui.common.VSpace
import iq.wasel.customer.ui.common.iqd
import iq.wasel.customer.ui.common.toast
import iq.wasel.customer.ui.theme.Wc

// ============================== حسابي ==============================

@Composable
fun AccountScreen(vm: AppViewModel, nav: Nav) {
    val ctx = LocalContext.current
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 32.dp),
    ) {
        // الرأس
        Column(
            Modifier
                .fillMaxWidth()
                .background(Wc.Ink)
                .statusBarsPadding()
                .padding(start = 20.dp, end = 20.dp, top = 24.dp, bottom = 56.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(64.dp)
                        .clip(CircleShape)
                        .background(Wc.Saffron),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("أ", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = Wc.Ink)
                }
                HSpace(14.dp)
                Column(Modifier.weight(1f)) {
                    Text("أحمد سالم", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = Color.White)
                    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                        Text("+964 770 123 4567", style = MaterialTheme.typography.bodyMedium, color = Color.White.copy(alpha = 0.7f))
                    }
                }
                Box(
                    Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.12f))
                        .clickable { ctx.toast("تعديل الملف الشخصي جاي بالنسخة الجاية") },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.Edit, contentDescription = "تعديل", tint = Color.White, modifier = Modifier.size(18.dp))
                }
            }
        }

        // أرقام سريعة تتداخل مع الرأس
        Row(
            Modifier
                .offset(y = (-36).dp)
                .padding(horizontal = 16.dp)
                .fillMaxWidth()
                .height(84.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            val delivered = vm.orders.count { it.status == OrderStatus.DELIVERED }
            StatTile("$delivered", "طلب وصل", Modifier.weight(1f))
            StatTile("${vm.favoriteStores.size + vm.favoriteProducts.size}", "بالمفضلة", Modifier.weight(1f))
            StatTile("${vm.addresses.size}", "عناوين", Modifier.weight(1f))
        }

        MenuGroup("حسابك") {
            MenuRow(Icons.Rounded.LocationOn, Wc.Primary, "عناويني", "${vm.addresses.size} عنوان محفوظ") { nav.go(Route.Addresses) }
            MenuDivider()
            MenuRow(Icons.Rounded.Favorite, Wc.Danger, "المفضلة", "متاجر ومنتجات تحبها") { nav.go(Route.Favorites) }
            MenuDivider()
            MenuRow(
                Icons.Rounded.Notifications,
                Wc.Saffron,
                "الإشعارات",
                if (vm.quietHours) "أوقات الهدوء مفعّلة" else "كل الإشعارات شغّالة",
            ) { nav.go(Route.Notifications) }
        }

        MenuGroup("المساعدة") {
            MenuRow(Icons.Rounded.SupportAgent, Wc.Primary, "احچي ويانا", "عندك مشكلة بطلب؟ نرد عليك بسرعة") {
                ctx.toast("الدعم المباشر جاي بالنسخة الجاية")
            }
            MenuDivider()
            MenuRow(Icons.Rounded.Info, Wc.Muted, "عن واصل", "نسخة تجريبية 0.1") { ctx.toast("واصل · نسخة تجريبية") }
            MenuDivider()
            MenuRow(Icons.AutoMirrored.Rounded.Logout, Wc.Danger, "تسجيل الخروج", null, danger = true) {
                ctx.toast("هاي نسخة تجريبية، ما اكو حساب حقيقي")
            }
        }
    }
}

@Composable
private fun StatTile(value: String, label: String, modifier: Modifier) {
    Column(
        modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(18.dp))
            .background(Wc.Card)
            .border(1.dp, Wc.Line, RoundedCornerShape(18.dp))
            .padding(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = Wc.Ink)
        Text(label, style = MaterialTheme.typography.labelMedium, color = Wc.Muted)
    }
}

@Composable
private fun MenuGroup(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.padding(horizontal = 16.dp)) {
        Text(
            title,
            style = MaterialTheme.typography.labelLarge,
            color = Wc.Muted,
            modifier = Modifier.padding(start = 6.dp, top = 22.dp, bottom = 8.dp),
        )
        Panel(padding = 6.dp, content = content)
    }
}

@Composable
private fun MenuDivider() = HorizontalDivider(color = Wc.Line, modifier = Modifier.padding(horizontal = 12.dp))

@Composable
private fun MenuRow(
    icon: ImageVector,
    tint: Color,
    title: String,
    subtitle: String?,
    danger: Boolean = false,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(tint.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
        }
        HSpace(12.dp)
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Medium, color = if (danger) Wc.Danger else Wc.Ink)
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
            }
        }
        if (!danger) {
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = Wc.Muted.copy(alpha = 0.6f))
        }
    }
}

// ============================== المفضلة ==============================

@Composable
fun FavoritesScreen(vm: AppViewModel, nav: Nav) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val stores = DemoData.stores.filter { it.id in vm.favoriteStores }
    val products = DemoData.products.filter { it.id in vm.favoriteProducts }

    Column(
        Modifier
            .fillMaxSize()
            .background(Wc.Cream),
    ) {
        TopBar("المفضلة", onBack = nav::back)
        Row(
            Modifier
                .padding(horizontal = 16.dp)
                .fillMaxWidth()
                .clip(CircleShape)
                .background(Color(0xFFECE7DE))
                .padding(4.dp),
        ) {
            listOf("المتاجر (${stores.size})", "المنتجات (${products.size})").forEachIndexed { i, label ->
                val selected = tab == i
                Text(
                    label,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (selected) Wc.Ink else Wc.Muted,
                    modifier = Modifier
                        .weight(1f)
                        .clip(CircleShape)
                        .background(if (selected) Wc.Card else Color.Transparent)
                        .clickable { tab = i }
                        .padding(vertical = 10.dp),
                    textAlign = TextAlign.Center,
                )
            }
        }
        VSpace(8.dp)

        if (tab == 0) {
            if (stores.isEmpty()) {
                EmptyState(Icons.Rounded.FavoriteBorder, "لسه ما ضفت متجر", "اضغط على القلب بأي متجر حتى يطلع هنا")
            } else {
                LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
                    items(stores, key = { it.id }) { s ->
                        StoreRow(s, true, onFavorite = { vm.toggleFavStore(s.id) }) { nav.go(Route.StoreR(s.id)) }
                    }
                }
            }
        } else {
            if (products.isEmpty()) {
                EmptyState(Icons.Rounded.FavoriteBorder, "لسه ما ضفت منتج", "اضغط على القلب جنب أي منتج داخل المتجر")
            } else {
                LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
                    items(products, key = { it.id }) { p ->
                        val store = DemoData.store(p.storeId) ?: return@items
                        Row(
                            Modifier
                                .padding(horizontal = 16.dp, vertical = 5.dp)
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(18.dp))
                                .background(Wc.Card)
                                .border(1.dp, Wc.Line, RoundedCornerShape(18.dp))
                                .clickable { nav.go(Route.StoreR(store.id)) }
                                .padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            StoreBadge(store, 44.dp)
                            HSpace(12.dp)
                            Column(Modifier.weight(1f)) {
                                Text(p.name, fontWeight = FontWeight.SemiBold, color = Wc.Ink)
                                Text("${store.name} · ${p.price.iqd()}", style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
                            }
                            Icon(
                                Icons.Rounded.Favorite,
                                contentDescription = "شيل من المفضلة",
                                tint = Wc.Danger,
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .clickable { vm.toggleFavProduct(p.id) }
                                    .padding(8.dp)
                                    .size(20.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

// ============================== العناوين ==============================

@Composable
fun AddressesScreen(vm: AppViewModel, nav: Nav) {
    val ctx = LocalContext.current
    Column(
        Modifier
            .fillMaxSize()
            .background(Wc.Cream),
    ) {
        TopBar("عناويني", onBack = nav::back)
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            vm.addresses.forEach { a ->
                val selected = vm.selectedAddressId == a.id
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(20.dp))
                        .background(Wc.Card)
                        .border(1.5.dp, if (selected) Wc.Primary else Wc.Line, RoundedCornerShape(20.dp))
                        .clickable { vm.selectedAddressId = a.id }
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = selected,
                        onClick = { vm.selectedAddressId = a.id },
                        colors = RadioButtonDefaults.colors(selectedColor = Wc.Primary),
                    )
                    Column(Modifier.weight(1f)) {
                        Text(a.label, fontWeight = FontWeight.SemiBold, color = Wc.Ink)
                        Text(a.details, style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
                        Text("علامة دالة: ${a.landmark}", style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
                    }
                }
            }
            VSpace(4.dp)
            OutlinedButton(
                onClick = { ctx.toast("تحديد العنوان من الخريطة جاي بالنسخة الجاية") },
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
            ) {
                Text("+ إضافة عنوان جديد", color = Wc.Primary, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

// ============================== الإشعارات ==============================

@Composable
fun NotificationsScreen(vm: AppViewModel, nav: Nav) {
    Column(
        Modifier
            .fillMaxSize()
            .background(Wc.Cream),
    ) {
        TopBar("الإشعارات", onBack = nav::back)
        Column(Modifier.padding(horizontal = 16.dp)) {
            Panel(padding = 6.dp) {
                SwitchRow(
                    "تحديثات الطلب",
                    "دائماً شغّالة حتى توصلك حالة طلبك أول بأول",
                    checked = true,
                    enabled = false,
                ) {}
                MenuDivider()
                SwitchRow("العروض والخصومات", "خصومات المتاجر القريبة منك", vm.notifOffers) { vm.notifOffers = it }
                MenuDivider()
                SwitchRow("متاجر جديدة", "لما ينفتح متجر جديد بمنطقتك", vm.notifNewStores) { vm.notifNewStores = it }
                MenuDivider()
                SwitchRow("أوقات الهدوء", "بدون صوت من 12 بالليل لـ 8 الصبح", vm.quietHours) { vm.quietHours = it }
            }
            VSpace(12.dp)
            Text(
                "بالتطبيق الحقيقي هاي الإعدادات تنحفظ بالخادم، فتشتغل حتى لو بدّلت الموبايل.",
                style = MaterialTheme.typography.bodySmall,
                color = Wc.Muted,
                modifier = Modifier.padding(horizontal = 8.dp),
            )
        }
    }
}

@Composable
private fun SwitchRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    enabled: Boolean = true,
    onChange: (Boolean) -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Medium, color = Wc.Ink)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
        }
        HSpace(8.dp)
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            enabled = enabled,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = Wc.Primary,
                disabledCheckedTrackColor = Wc.Primary.copy(alpha = 0.45f),
                disabledCheckedThumbColor = Color.White,
            ),
        )
    }
}
