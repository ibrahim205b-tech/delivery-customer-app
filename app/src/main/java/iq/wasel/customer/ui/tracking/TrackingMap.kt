package iq.wasel.customer.ui.tracking

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import iq.wasel.customer.data.GeoP
import iq.wasel.customer.ui.theme.Wc
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline
import java.io.File

private fun GeoP.toGeoPoint() = GeoPoint(lat, lng)

/** دائرة ملوّنة بحلقة بيضاء، تُستخدم كعلامة على الخريطة. */
private fun dotDrawable(ctx: Context, fill: Int, sizeDp: Int, innerDot: Boolean): Drawable {
    val d = ctx.resources.displayMetrics.density
    val s = (sizeDp * d).toInt()
    val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
    val c = Canvas(bmp)
    val p = Paint(Paint.ANTI_ALIAS_FLAG)
    p.color = 0x33000000
    c.drawCircle(s / 2f, s / 2f, s / 2f, p)
    p.color = android.graphics.Color.WHITE
    c.drawCircle(s / 2f, s / 2f, s / 2f - 1.5f * d, p)
    p.color = fill
    c.drawCircle(s / 2f, s / 2f, s / 2f - 4.5f * d, p)
    if (innerDot) {
        p.color = android.graphics.Color.WHITE
        c.drawCircle(s / 2f, s / 2f, s / 7f, p)
    }
    return BitmapDrawable(ctx.resources, bmp)
}

/**
 * خريطة OpenStreetMap (مجانية) فيها: المتجر، البيت، السائق، والمسار.
 */
@Composable
fun TrackingMap(
    store: GeoP,
    home: GeoP,
    driver: GeoP?,
    route: List<GeoP>,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle

    val mapView = remember {
        Configuration.getInstance().apply {
            userAgentValue = context.packageName
            osmdroidBasePath = File(context.cacheDir, "osm")
            osmdroidTileCache = File(context.cacheDir, "osm/tiles")
        }
        MapView(context).apply {
            setTileSource(TileSourceFactory.MAPNIK)
            setMultiTouchControls(true)
            zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
            isTilesScaledToDpi = true
            controller.setZoom(15.3)
            val midLat = (store.lat + home.lat) / 2
            val midLng = (store.lng + home.lng) / 2
            // نزحزح المركز شوية لفوق لأن اللوحة السفلية تغطي نص الخريطة
            controller.setCenter(GeoPoint(midLat - 0.0045, midLng))
        }
    }

    val routeLine = remember {
        Polyline(mapView).apply {
            outlinePaint.color = Wc.Primary.toArgb()
            outlinePaint.strokeWidth = 9f * context.resources.displayMetrics.density / 2f
            outlinePaint.strokeCap = Paint.Cap.ROUND
            outlinePaint.strokeJoin = Paint.Join.ROUND
        }
    }

    fun marker(fill: Int, size: Int, inner: Boolean) = Marker(mapView).apply {
        icon = dotDrawable(context, fill, size, inner)
        setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
        setOnMarkerClickListener { _, _ -> true }
    }

    val storeMarker = remember { marker(Wc.Ink.toArgb(), 26, false) }
    val homeMarker = remember { marker(Wc.Primary.toArgb(), 26, true) }
    val driverMarker = remember { marker(Wc.Saffron.toArgb(), 34, true) }

    DisposableEffect(lifecycle) {
        mapView.overlays.add(routeLine)
        mapView.overlays.add(storeMarker)
        mapView.overlays.add(homeMarker)
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> mapView.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        mapView.onResume()
        onDispose {
            lifecycle.removeObserver(observer)
            mapView.onPause()
            mapView.onDetach()
        }
    }

    AndroidView(factory = { mapView }, modifier = modifier) { map ->
        storeMarker.position = store.toGeoPoint()
        homeMarker.position = home.toGeoPoint()
        routeLine.setPoints(route.map { it.toGeoPoint() })
        if (driver != null) {
            driverMarker.position = driver.toGeoPoint()
            if (!map.overlays.contains(driverMarker)) map.overlays.add(driverMarker)
        } else {
            map.overlays.remove(driverMarker)
        }
        map.invalidate()
    }
}
