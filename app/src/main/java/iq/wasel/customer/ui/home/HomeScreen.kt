package iq.wasel.customer.ui.home

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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.NotificationsNone
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.SearchOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import iq.wasel.customer.AppViewModel
import iq.wasel.customer.Nav
import iq.wasel.customer.Route
import iq.wasel.customer.data.Category
import iq.wasel.customer.data.DemoData
import iq.wasel.customer.data.Order
import iq.wasel.customer.data.Product
import iq.wasel.customer.ui.common.AddButton
import iq.wasel.customer.ui.common.EmptyState
import iq.wasel.customer.ui.common.HSpace
import iq.wasel.customer.ui.common.QtyStepper
import iq.wasel.customer.ui.common.SectionHeader
import iq.wasel.customer.ui.common.StepBar
import iq.wasel.customer.ui.common.StoreBadge
import iq.wasel.customer.ui.common.StoreRow
import iq.wasel.customer.ui.common.VSpace
import iq.wasel.customer.ui.common.iqd
import iq.wasel.customer.ui.common.toast
import iq.wasel.customer.ui.theme.Wc
import java.time.LocalTime

@Composable
fun HomeScreen(vm: AppViewModel, nav: Nav) {
    var query by rememberSaveable { mutableStateOf("") }
    var selectedCat by rememberSaveable { mutableStateOf<String?>(null) }
    var showAddresses by remember { mutableStateOf(false) }
    val ctx = LocalContext.current
    val active = vm.orders.firstOrNull { it.status.isActive }

    val cat = selectedCat
    val storeList = DemoData.stores
        .filter { cat == null || it.categoryId == cat }
        .sortedBy { it.etaMinutes }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 120.dp)) {
        item {
            HomeHeader(vm, onAddressClick = { showAddresses = true }, onBell = { ctx.toast("ما عندك إشعارات جديدة") })
        }
        item {
            SearchBox(query, onChange = { query = it })
        }

        if (query.isNotBlank()) {
            val results = DemoData.search(query)
            if (results.isEmpty()) {
                item {
                    EmptyState(
                        Icons.Rounded.SearchOff,
                        "ما لگينا \"$query\"",
                        "جرّب كلمة ثانية، أو اطلبه كطلب خاص",
                    )
                }
            } else {
                item { SectionHeader("النتائج", "${results.size} نتيجة") }
                items(results, key = { it.id }) { p ->
                    SearchResultRow(p, vm, onOpenStore = { nav.go(Route.StoreR(p.storeId)) })
                }
            }
        } else {
            if (active != null) {
                item { ActiveOrderBanner(active) { nav.go(Route.Tracking(active.id)) } }
            }
            item {
                CategoriesRow(selectedCat) { id -> selectedCat = if (selectedCat == id) null else id }
            }
            item {
                SpecialRequestCard { ctx.toast("الطلب الخاص جاي بالنسخة الجاية") }
            }
            item {
                SectionHeader(
                    if (cat == null) "يوصلك أسرع" else DemoData.category(cat)?.name ?: "",
                    "${storeList.size} متجر",
                )
            }
            items(storeList, key = { it.id }) { s ->
                StoreRow(
                    store = s,
                    isFavorite = s.id in vm.favoriteStores,
                    onFavorite = { vm.toggleFavStore(s.id) },
                    onClick = { nav.go(Route.StoreR(s.id)) },
                )
            }
        }
    }

    if (showAddresses) {
        AddressSheet(vm, onDismiss = { showAddresses = false })
    }
}

@Composable
private fun HomeHeader(vm: AppViewModel, onAddressClick: () -> Unit, onBell: () -> Unit) {
    val addr = vm.selectedAddress
    val greeting = if (LocalTime.now().hour < 12) "صباح الخير" else "مساء الخير"
    Column(
        Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(start = 20.dp, end = 12.dp, top = 12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(12.dp))
                    .clickable(onClick = onAddressClick)
                    .padding(vertical = 4.dp),
            ) {
                Text("التوصيل إلى", style = MaterialTheme.typography.labelMedium, color = Wc.Muted)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "${addr.label} · ${addr.details}",
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = Wc.Ink,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    Icon(Icons.Rounded.KeyboardArrowDown, contentDescription = null, tint = Wc.Ink)
                }
            }
            Box(
                Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .clickable(onClick = onBell),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.NotificationsNone, contentDescription = "الإشعارات", tint = Wc.Ink)
            }
        }
        VSpace(18.dp)
        Text("$greeting، أحمد", style = MaterialTheme.typography.bodyLarge, color = Wc.Muted)
        Text(
            "شنو تحتاج اليوم؟",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = Wc.Ink,
        )
    }
}

@Composable
private fun SearchBox(value: String, onChange: (String) -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Row(
        Modifier
            .padding(horizontal = 16.dp, vertical = 14.dp)
            .fillMaxWidth()
            .height(54.dp)
            .clip(shape)
            .background(Wc.Card)
            .border(1.dp, Wc.Line, shape)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.Search, contentDescription = null, tint = Wc.Muted)
        HSpace(10.dp)
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) {
                Text("دوّر على أكلة، منتج، أو متجر", style = MaterialTheme.typography.bodyLarge, color = Wc.Muted.copy(alpha = 0.7f))
            }
            BasicTextField(
                value = value,
                onValueChange = onChange,
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = Wc.Ink),
                cursorBrush = SolidColor(Wc.Primary),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (value.isNotEmpty()) {
            Icon(
                Icons.Rounded.Close,
                contentDescription = "مسح",
                tint = Wc.Muted,
                modifier = Modifier
                    .clip(CircleShape)
                    .clickable { onChange("") }
                    .padding(4.dp),
            )
        }
    }
}

@Composable
private fun CategoriesRow(selected: String?, onSelect: (String) -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(DemoData.categories, key = { it.id }) { c ->
            CategoryTile(c, c.id == selected) { onSelect(c.id) }
        }
    }
}

@Composable
private fun CategoryTile(c: Category, selected: Boolean, onClick: () -> Unit) {
    Column(
        Modifier
            .width(76.dp)
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(64.dp)
                .clip(RoundedCornerShape(20.dp))
                .background(if (selected) c.tint else c.tint.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(c.icon, contentDescription = null, tint = if (selected) Color.White else c.tint, modifier = Modifier.size(28.dp))
        }
        VSpace(6.dp)
        Text(
            c.name,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = Wc.Ink,
            textAlign = TextAlign.Center,
            maxLines = 2,
        )
    }
}

@Composable
private fun ActiveOrderBanner(order: Order, onClick: () -> Unit) {
    Row(
        Modifier
            .padding(horizontal = 16.dp)
            .padding(bottom = 16.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(Wc.Ink)
            .clickable(onClick = onClick)
            .padding(18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text("طلبك من ${order.store.name}", style = MaterialTheme.typography.labelMedium, color = Color.White.copy(alpha = 0.7f))
            Text(order.status.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = Color.White)
            VSpace(12.dp)
            StepBar(order.status.step, onDark = true)
        }
        HSpace(12.dp)
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = "تتبع", tint = Wc.Saffron)
    }
}

@Composable
private fun SpecialRequestCard(onClick: () -> Unit) {
    Row(
        Modifier
            .padding(horizontal = 16.dp, vertical = 14.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(Wc.SaffronSoft)
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(Wc.Saffron),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Rounded.EditNote, contentDescription = null, tint = Wc.Ink)
        }
        HSpace(12.dp)
        Column(Modifier.weight(1f)) {
            Text("ما لگيت اللي تريده؟", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = Wc.Ink)
            Text("اكتب طلبك بكلامك، وسائقنا يشتريه ويوصله", style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
        }
        Text("اطلب", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = Wc.Primary)
    }
}

@Composable
private fun SearchResultRow(p: Product, vm: AppViewModel, onOpenStore: () -> Unit) {
    val store = DemoData.store(p.storeId) ?: return
    val qty = vm.qtyOf(p.id)
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpenStore)
            .padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StoreBadge(store, 44.dp)
        HSpace(12.dp)
        Column(Modifier.weight(1f)) {
            Text(p.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = Wc.Ink)
            Text("${store.name} · ${p.price.iqd()}", style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
        }
        if (qty == 0) AddButton { vm.add(p) } else QtyStepper(qty, { vm.add(p) }, { vm.remove(p) })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddressSheet(vm: AppViewModel, onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Wc.Card) {
        Column(
            Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp)
                .padding(bottom = 20.dp),
        ) {
            Text("وين نوصلك؟", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = Wc.Ink)
            VSpace(12.dp)
            vm.addresses.forEach { a ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .clickable {
                            vm.selectedAddressId = a.id
                            onDismiss()
                        }
                        .padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = vm.selectedAddressId == a.id,
                        onClick = {
                            vm.selectedAddressId = a.id
                            onDismiss()
                        },
                        colors = RadioButtonDefaults.colors(selectedColor = Wc.Primary),
                    )
                    Column(Modifier.weight(1f)) {
                        Text(a.label, fontWeight = FontWeight.SemiBold, color = Wc.Ink)
                        Text(a.details, style = MaterialTheme.typography.bodySmall, color = Wc.Muted)
                    }
                }
            }
            VSpace(8.dp)
            Text(
                "+ عنوان جديد",
                color = Wc.Primary,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .clip(RoundedCornerShape(10.dp))
                    .clickable { ctx.toast("إضافة العناوين من الخريطة جاية بالنسخة الجاية") }
                    .padding(12.dp),
            )
            Spacer(Modifier.height(8.dp))
        }
    }
}
