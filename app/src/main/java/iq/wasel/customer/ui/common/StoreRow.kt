package iq.wasel.customer.ui.common

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import iq.wasel.customer.data.Store
import iq.wasel.customer.ui.theme.Wc

@Composable
fun StoreRow(store: Store, isFavorite: Boolean, onFavorite: () -> Unit, onClick: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Row(
        Modifier
            .padding(horizontal = 16.dp, vertical = 5.dp)
            .fillMaxWidth()
            .clip(shape)
            .background(Wc.Card)
            .border(1.dp, Wc.Line, shape)
            .clickable(onClick = onClick)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StoreBadge(store, 58.dp)
        HSpace(14.dp)
        Column(Modifier.weight(1f)) {
            Text(
                store.name,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = Wc.Ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                store.tagline,
                style = MaterialTheme.typography.bodySmall,
                color = Wc.Muted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            VSpace(6.dp)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Star, contentDescription = null, tint = Wc.Saffron, modifier = Modifier.size(15.dp))
                HSpace(3.dp)
                Text("${store.rating}", style = MaterialTheme.typography.labelMedium, color = Wc.Ink)
                MetaDot()
                Text("${store.etaMinutes} دقيقة", style = MaterialTheme.typography.labelMedium, color = Wc.Ink)
                MetaDot()
                Text("توصيل ${store.deliveryFee.iqd()}", style = MaterialTheme.typography.labelMedium, color = Wc.Muted)
            }
        }
        Icon(
            if (isFavorite) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
            contentDescription = "مفضلة",
            tint = if (isFavorite) Wc.Danger else Wc.Muted.copy(alpha = 0.6f),
            modifier = Modifier
                .clip(CircleShape)
                .clickable(onClick = onFavorite)
                .padding(8.dp)
                .size(20.dp),
        )
    }
}
