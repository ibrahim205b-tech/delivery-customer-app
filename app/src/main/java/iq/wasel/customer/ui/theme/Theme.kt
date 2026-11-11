package iq.wasel.customer.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import iq.wasel.customer.R

/** ألوان واصل: أخضر حبري عميق + زعفراني دافئ على خلفية كريمية. */
object Wc {
    val Ink = Color(0xFF12302D)
    val Primary = Color(0xFF1F6B5C)
    val PrimarySoft = Color(0xFFE2EEE9)
    val Saffron = Color(0xFFE9A23B)
    val SaffronSoft = Color(0xFFFBEFD9)
    val Cream = Color(0xFFF6F3ED)
    val Card = Color(0xFFFFFFFF)
    val Line = Color(0xFFE7E2D9)
    val Muted = Color(0xFF6E7672)
    val Danger = Color(0xFFC0473F)
    val DangerSoft = Color(0xFFF8E3E1)
}

val Plex = FontFamily(
    Font(R.font.plex_regular, FontWeight.Normal),
    Font(R.font.plex_medium, FontWeight.Medium),
    Font(R.font.plex_semibold, FontWeight.SemiBold),
    Font(R.font.plex_bold, FontWeight.Bold),
)

private val base = Typography()

private val AppTypography = Typography(
    displayLarge = base.displayLarge.copy(fontFamily = Plex),
    displayMedium = base.displayMedium.copy(fontFamily = Plex),
    displaySmall = base.displaySmall.copy(fontFamily = Plex),
    headlineLarge = base.headlineLarge.copy(fontFamily = Plex),
    headlineMedium = base.headlineMedium.copy(fontFamily = Plex),
    headlineSmall = base.headlineSmall.copy(fontFamily = Plex),
    titleLarge = base.titleLarge.copy(fontFamily = Plex),
    titleMedium = base.titleMedium.copy(fontFamily = Plex),
    titleSmall = base.titleSmall.copy(fontFamily = Plex),
    bodyLarge = base.bodyLarge.copy(fontFamily = Plex),
    bodyMedium = base.bodyMedium.copy(fontFamily = Plex),
    bodySmall = base.bodySmall.copy(fontFamily = Plex),
    labelLarge = base.labelLarge.copy(fontFamily = Plex),
    labelMedium = base.labelMedium.copy(fontFamily = Plex),
    labelSmall = base.labelSmall.copy(fontFamily = Plex),
)

private val AppColors = lightColorScheme(
    primary = Wc.Primary,
    onPrimary = Color.White,
    primaryContainer = Wc.PrimarySoft,
    onPrimaryContainer = Wc.Ink,
    secondary = Wc.Saffron,
    onSecondary = Wc.Ink,
    secondaryContainer = Wc.SaffronSoft,
    onSecondaryContainer = Wc.Ink,
    background = Wc.Cream,
    onBackground = Wc.Ink,
    surface = Color.White,
    onSurface = Wc.Ink,
    surfaceVariant = Color(0xFFF0ECE4),
    onSurfaceVariant = Wc.Muted,
    surfaceTint = Wc.Primary,
    outline = Wc.Line,
    outlineVariant = Wc.Line,
    error = Wc.Danger,
    surfaceContainerLowest = Color.White,
    surfaceContainerLow = Color(0xFFFBF9F5),
    surfaceContainer = Color(0xFFF6F3ED),
    surfaceContainerHigh = Color(0xFFF1EDE6),
    surfaceContainerHighest = Color(0xFFEAE5DC),
)

@Composable
fun WaselTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = AppColors, typography = AppTypography, content = content)
}
