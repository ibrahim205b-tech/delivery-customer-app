package iq.wasel.customer.ui.store

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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.DeliveryDining
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Storefront
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import iq.wasel.customer.AppViewModel
import iq.wasel.customer.Nav
import iq.wasel.customer.data.DemoData
import iq.wasel.customer.data.Product
import iq.wasel.customer.data.Store
import iq.wasel.customer.ui.common.AddButton
import iq.wasel.customer.ui.common.CircleIcon
import iq.wasel.customer.ui.common.HSpace
import iq.wasel.customer.ui.common.QtyStepper
import iq.wasel.customer.ui.common.StoreBadge
import iq.wasel.customer.ui.common.VSpace
import iq.wasel.customer.ui.common.iqd
import iq.wasel.customer.ui.theme.Wc

@Composable
fun StoreScreen(vm: AppViewModel, nav: Nav, storeId: String) {
    val store = DemoData.store(storeId) ?: return
    val sections = DemoData.productsOf(storeId).groupBy { it.section }
    val categoryIcon = DemoData.category(store.categoryId)?.icon ?: Icons.Rounded.Storefront

    LazyColumn(
        Modifier
            .fillMaxSize()
            .background(Wc.Cream),
        contentPadding = PaddingValues(bottom = 120.dp),
    ) {
        item {
            StoreHero(
                store = store,
                decoration = categoryIcon,
                isFavorite = store.id in vm.favoriteStores,
                onBack = nav::back,
                onFavorite = { vm.toggleFavStore(store.id) },
            )
        }
        sections.forEach { (section, list) ->
            item(key = "h_$section") {
                Text(
                    section,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = Wc.Ink,
                    modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 8.dp),
                )
            }
            items(list, key = { it.id }) { p ->
                ProductRow(
                    product = p,
                    store = store,
                    decoration = categoryIcon,
                    qty = vm.qtyOf(p.id),
                    isFavorite = p.id in vm.favoriteProducts,
                    onAdd = { vm.add(p) },
                    onRemove = { vm.remove(p) },
                    onFavorite = { vm.toggleFavProduct(p.id) },
                )
            }
        }
    }
}

@Composable
private fun StoreHero(
    store: Store,
    decoration: ImageVector,
    isFavorite: Boolean,
    onBack: () -> Unit,
    onFavorite: () -> Unit,
) {
    Box(Modifier.fillMaxWidth()) {
        // الغلاف الملوّن بلون المتجر
        Box(
            Modifier
                .fillMaxWidth()
                .height(210.dp)
                .background(Brush.verticalGradient(listOf(store.color, store.color.copy(alpha = 0.82f)))),
        ) {
            Icon(
                decoration,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.10f),
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .offset(x = (-20).dp, y = 10.dp)
                    .size(170.dp),
            )
            Row(
                Modifier
                    .statusBarsPadding()
                    .padding(12.dp)
                    .fillMaxWidth(),
            ) {
                CircleIcon(Icons.AutoMirrored.Rounded.ArrowBack, "رجوع", Color.White.copy(alpha = 0.22f), Color.White, onClick = onBack)
                Spacer(Modifier.weight(1f))
                CircleIcon(
                    if (isFavorite) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                    "مفضلة",
                    Color.White.copy(alpha = 0.22f),
                    Color.White,
                    onClick = onFavorite,
                )
            }
        }
        // بطاقة معلومات المتجر فوق الغلاف
        Column(
            Modifier
                .padding(top = 150.dp, start = 16.dp, end = 16.dp)
                .fillMaxWidth()
                .shadow(8.dp, RoundedCornerShape(24.dp))
                .clip(RoundedCornerShape(24.dp))
                .background(Wc.Card)
                .padding(18.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                StoreBadge(store, 54.dp)
                HSpace(14.dp)
                Column(Modifier.weight(1f)) {
                    Text(store.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = Wc.Ink)
                    Text(store.tagline, style = MaterialTheme.typography.bodyMedium, color = Wc.Muted)
                }
            }
            VSpace(14.dp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                InfoChip(Icons.Rounded.Star, "${store.rating}", Wc.Saffron)
                InfoChip(Icons.Rounded.Schedule, "${store.etaMinutes} دقيقة", Wc.Primary)
                InfoChip(Icons.Rounded.DeliveryDining, store.deliveryFee.iqd(), Wc.Primary)
            }
        }
    }
}

@Composable
private fun InfoChip(icon: ImageVector, text: String, tint: Color) {
    Row(
        Modifier
            .clip(CircleShape)
            .background(Wc.Cream)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(16.dp))
        HSpace(4.dp)
        Text(text, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Medium, color = Wc.Ink)
    }
}

@Composable
private fun ProductRow(
    product: Product,
    store: Store,
    decoration: ImageVector,
    qty: Int,
    isFavorite: Boolean,
    onAdd: () -> Unit,
    onRemove: () -> Unit,
    onFavorite: () -> Unit,
) {
    val shape = RoundedCornerShape(20.dp)
    Row(
        Modifier
            .padding(horizontal = 16.dp, vertical = 5.dp)
            .fillMaxWidth()
            .clip(shape)
            .background(Wc.Card)
            .border(1.dp, if (qty > 0) Wc.Primary.copy(alpha = 0.5f) else Wc.Line, shape)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    product.name,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = Wc.Ink,
                    modifier = Modifier.weight(1f, fill = false),
                )
                Icon(
                    if (isFavorite) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                    contentDescription = "مفضلة",
                    tint = if (isFavorite) Wc.Danger else Wc.Muted.copy(alpha = 0.5f),
                    modifier = Modifier
                        .clip(CircleShape)
                        .clickable(onClick = onFavorite)
                        .padding(6.dp)
                        .size(16.dp),
                )
            }
            Text(product.description, style = MaterialTheme.typography.bodySmall, color = Wc.Muted, maxLines = 2)
            VSpace(8.dp)
            Text(product.price.iqd(), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold, color = Wc.Primary)
        }
        HSpace(12.dp)
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                Modifier
                    .size(78.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(store.color.copy(alpha = 0.10f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(decoration, contentDescription = null, tint = store.color.copy(alpha = 0.55f), modifier = Modifier.size(34.dp))
            }
            VSpace(8.dp)
            if (qty == 0) AddButton(onAdd) else QtyStepper(qty, onAdd, onRemove)
        }
    }
}
