package iq.wasel.customer.ui.common

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import iq.wasel.customer.data.Store
import iq.wasel.customer.ui.theme.Wc
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

// ---------------- تنسيق ----------------

fun Int.iqd(): String = String.format(Locale.US, "%,d", this) + " د.ع"

val iraqiMonths = listOf(
    "كانون الثاني", "شباط", "آذار", "نيسان", "أيار", "حزيران",
    "تموز", "آب", "أيلول", "تشرين الأول", "تشرين الثاني", "كانون الأول",
)

fun formatDateTime(ms: Long): String {
    val t = Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault())
    val h12 = if (t.hour % 12 == 0) 12 else t.hour % 12
    val ampm = if (t.hour < 12) "ص" else "م"
    return "${t.dayOfMonth} ${iraqiMonths[t.monthValue - 1]} · $h12:${"%02d".format(t.minute)} $ampm"
}

// ---------------- مسافات ----------------

@Composable
fun VSpace(h: Dp) = Spacer(Modifier.height(h))

@Composable
fun HSpace(w: Dp) = Spacer(Modifier.width(w))

// ---------------- عناصر مشتركة ----------------

@Composable
fun Panel(
    modifier: Modifier = Modifier,
    padding: Dp = 16.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Wc.Card)
            .border(1.dp, Wc.Line, shape)
            .padding(padding),
        content = content,
    )
}

/** شعار المتجر: مربع بلون المتجر وأول حرف من اسمه. */
@Composable
fun StoreBadge(store: Store, size: Dp) {
    Box(
        Modifier
            .size(size)
            .clip(RoundedCornerShape(size * 0.3f))
            .background(store.color),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            store.name.take(1),
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = (size.value * 0.42f).sp,
        )
    }
}

@Composable
fun TopBar(title: String, onBack: () -> Unit, actions: @Composable () -> Unit = {}) {
    Row(
        Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .height(60.dp)
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "رجوع", tint = Wc.Ink)
        }
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = Wc.Ink)
        Spacer(Modifier.weight(1f))
        actions()
    }
}

@Composable
fun SectionHeader(title: String, trailing: String? = null, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .padding(start = 20.dp, end = 20.dp, top = 22.dp, bottom = 10.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = Wc.Ink)
        Spacer(Modifier.weight(1f))
        if (trailing != null) {
            Text(trailing, style = MaterialTheme.typography.labelMedium, color = Wc.Muted)
        }
    }
}

@Composable
fun MetaDot() {
    Box(
        Modifier
            .padding(horizontal = 6.dp)
            .size(3.dp)
            .clip(CircleShape)
            .background(Wc.Muted.copy(alpha = 0.5f)),
    )
}

/** شريط التقدّم بأربع قطع: أُرسل · يتجهّز · بالطريق · وصل */
@Composable
fun StepBar(step: Int, onDark: Boolean, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(4) { i ->
            val done = i <= step
            Box(
                Modifier
                    .weight(1f)
                    .height(6.dp)
                    .clip(CircleShape)
                    .background(
                        when {
                            done -> Wc.Saffron
                            onDark -> Color.White.copy(alpha = 0.18f)
                            else -> Wc.Line
                        },
                    ),
            )
        }
    }
}

@Composable
fun QtyStepper(qty: Int, onAdd: () -> Unit, onRemove: () -> Unit) {
    Row(
        Modifier
            .clip(CircleShape)
            .background(Wc.Ink)
            .padding(horizontal = 4.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.Rounded.Remove, contentDescription = "نقّص", tint = Color.White,
            modifier = Modifier
                .clip(CircleShape)
                .clickable(onClick = onRemove)
                .padding(6.dp)
                .size(16.dp),
        )
        Text(
            "$qty", color = Color.White, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 6.dp),
        )
        Icon(
            Icons.Rounded.Add, contentDescription = "زيد", tint = Color.White,
            modifier = Modifier
                .clip(CircleShape)
                .clickable(onClick = onAdd)
                .padding(6.dp)
                .size(16.dp),
        )
    }
}

@Composable
fun AddButton(onClick: () -> Unit) {
    Box(
        Modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(Color.White)
            .border(1.5.dp, Wc.Ink, CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Rounded.Add, contentDescription = "أضف", tint = Wc.Ink, modifier = Modifier.size(18.dp))
    }
}

@Composable
fun CircleIcon(
    icon: ImageVector,
    contentDescription: String,
    background: Color,
    tint: Color,
    size: Dp = 44.dp,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .size(size)
            .clip(CircleShape)
            .background(background)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = contentDescription, tint = tint, modifier = Modifier.size(size * 0.48f))
    }
}

@Composable
fun EmptyState(icon: ImageVector, title: String, hint: String, modifier: Modifier = Modifier) {
    Column(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 32.dp, vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(72.dp)
                .clip(CircleShape)
                .background(Wc.PrimarySoft),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = Wc.Primary, modifier = Modifier.size(32.dp))
        }
        VSpace(16.dp)
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = Wc.Ink)
        VSpace(4.dp)
        Text(hint, style = MaterialTheme.typography.bodyMedium, color = Wc.Muted)
    }
}

fun android.content.Context.toast(msg: String) {
    Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
}
