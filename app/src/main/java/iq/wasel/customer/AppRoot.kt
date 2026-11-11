package iq.wasel.customer

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Receipt
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import iq.wasel.customer.data.DemoData
import iq.wasel.customer.ui.account.AccountScreen
import iq.wasel.customer.ui.account.AddressesScreen
import iq.wasel.customer.ui.account.FavoritesScreen
import iq.wasel.customer.ui.account.NotificationsScreen
import iq.wasel.customer.ui.activity.ActivityScreen
import iq.wasel.customer.ui.cart.CartScreen
import iq.wasel.customer.ui.common.HSpace
import iq.wasel.customer.ui.common.VSpace
import iq.wasel.customer.ui.common.iqd
import iq.wasel.customer.ui.home.HomeScreen
import iq.wasel.customer.ui.store.StoreScreen
import iq.wasel.customer.ui.theme.Wc
import iq.wasel.customer.ui.tracking.TrackingScreen

sealed interface Route {
    data object Tabs : Route
    data class StoreR(val id: String) : Route
    data object Cart : Route
    data class Tracking(val orderId: String) : Route
    data object Favorites : Route
    data object Addresses : Route
    data object Notifications : Route
}

/** تنقّل بسيط بمكدّس شاشات: go تفتح، back ترجع، replace تبدّل الحالية. */
class Nav(private val stack: SnapshotStateList<Route>) {
    fun go(route: Route) {
        stack.add(route)
    }

    fun back() {
        if (stack.size > 1) stack.removeAt(stack.lastIndex)
    }

    fun replace(route: Route) {
        if (stack.size > 1) stack.removeAt(stack.lastIndex)
        stack.add(route)
    }
}

enum class Tab(val label: String, val icon: ImageVector) {
    HOME("الرئيسية", Icons.Rounded.Home),
    ACTIVITY("نشاطي", Icons.Rounded.Receipt),
    ACCOUNT("حسابي", Icons.Rounded.Person),
}

@Composable
fun AppRoot(vm: AppViewModel = viewModel()) {
    val stack = remember { mutableStateListOf<Route>(Route.Tabs) }
    val nav = remember { Nav(stack) }
    var tab by rememberSaveable { mutableStateOf(Tab.HOME) }
    val current = stack.last()

    BackHandler(enabled = stack.size > 1 || tab != Tab.HOME) {
        if (stack.size > 1) nav.back() else tab = Tab.HOME
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Wc.Cream),
    ) {
        when (current) {
            Route.Tabs -> Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) {
                    when (tab) {
                        Tab.HOME -> HomeScreen(vm, nav)
                        Tab.ACTIVITY -> ActivityScreen(vm, nav)
                        Tab.ACCOUNT -> AccountScreen(vm, nav)
                    }
                }
                BottomBar(tab, activeOrders = vm.orders.count { it.status.isActive }) { tab = it }
            }
            is Route.StoreR -> StoreScreen(vm, nav, current.id)
            Route.Cart -> CartScreen(vm, nav)
            is Route.Tracking -> TrackingScreen(vm, nav, current.orderId)
            Route.Favorites -> FavoritesScreen(vm, nav)
            Route.Addresses -> AddressesScreen(vm, nav)
            Route.Notifications -> NotificationsScreen(vm, nav)
        }

        val showCartPill = vm.cartCount > 0 &&
            ((current is Route.Tabs && tab == Tab.HOME) || current is Route.StoreR)
        AnimatedVisibility(
            visible = showCartPill,
            enter = slideInVertically { it } + fadeIn(),
            exit = slideOutVertically { it } + fadeOut(),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(bottom = if (current is Route.Tabs) 84.dp else 16.dp),
        ) {
            CartPill(vm) { nav.go(Route.Cart) }
        }

        vm.pendingSwitch?.let { p ->
            val from = vm.cartStore?.name ?: ""
            val to = DemoData.store(p.storeId)?.name ?: ""
            AlertDialog(
                onDismissRequest = vm::dismissSwitch,
                containerColor = Color.White,
                title = { Text("نبدأ سلة جديدة؟", fontWeight = FontWeight.Bold) },
                text = { Text("سلتك بيها أغراض من $from. إذا ضفت من $to راح تنمسح السلة الحالية.") },
                confirmButton = {
                    TextButton(onClick = vm::confirmSwitch) { Text("سلة جديدة", color = Wc.Primary, fontWeight = FontWeight.SemiBold) }
                },
                dismissButton = {
                    TextButton(onClick = vm::dismissSwitch) { Text("خليها", color = Wc.Muted) }
                },
            )
        }
    }
}

@Composable
private fun BottomBar(selected: Tab, activeOrders: Int, onSelect: (Tab) -> Unit) {
    Surface(color = Color.White, shadowElevation = 12.dp) {
        Row(
            Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .height(68.dp)
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Tab.entries.forEach { t ->
                val isSel = t == selected
                Column(
                    Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(16.dp))
                        .clickable { onSelect(t) }
                        .padding(vertical = 6.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box {
                        Icon(
                            t.icon,
                            contentDescription = t.label,
                            tint = if (isSel) Wc.Ink else Wc.Muted.copy(alpha = 0.7f),
                            modifier = Modifier.size(24.dp),
                        )
                        if (t == Tab.ACTIVITY && activeOrders > 0) {
                            Box(
                                Modifier
                                    .align(Alignment.TopEnd)
                                    .size(9.dp)
                                    .clip(CircleShape)
                                    .background(Wc.Saffron),
                            )
                        }
                    }
                    VSpace(2.dp)
                    Text(
                        t.label,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = if (isSel) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (isSel) Wc.Ink else Wc.Muted,
                    )
                    VSpace(3.dp)
                    Box(
                        Modifier
                            .width(if (isSel) 18.dp else 0.dp)
                            .height(3.dp)
                            .clip(CircleShape)
                            .background(Wc.Saffron),
                    )
                }
            }
        }
    }
}

@Composable
private fun CartPill(vm: AppViewModel, onClick: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Row(
        Modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .shadow(12.dp, shape)
            .clip(shape)
            .background(Wc.Ink)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(30.dp)
                .clip(CircleShape)
                .background(Wc.Saffron),
            contentAlignment = Alignment.Center,
        ) {
            Text("${vm.cartCount}", fontWeight = FontWeight.Bold, color = Wc.Ink)
        }
        HSpace(12.dp)
        Column(Modifier.weight(1f)) {
            Text("عرض السلة", fontWeight = FontWeight.SemiBold, color = Color.White)
            Text(vm.cartStore?.name ?: "", style = MaterialTheme.typography.labelMedium, color = Color.White.copy(alpha = 0.7f))
        }
        Text(vm.cartSubtotal.iqd(), fontWeight = FontWeight.Bold, color = Color.White)
    }
}
