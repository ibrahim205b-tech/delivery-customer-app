package iq.wasel.customer.data

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BakeryDining
import androidx.compose.material.icons.rounded.LocalFlorist
import androidx.compose.material.icons.rounded.LocalGroceryStore
import androidx.compose.material.icons.rounded.LocalPharmacy
import androidx.compose.material.icons.rounded.Restaurant
import androidx.compose.material.icons.rounded.SoupKitchen
import androidx.compose.material.icons.rounded.Spa
import androidx.compose.ui.graphics.Color
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * بيانات تجريبية بدل الخادم. كل الأسماء والأماكن خيالية.
 * لاحقاً تنستبدل بطلبات API حقيقية بدون ما تتغير الشاشات.
 */
object DemoData {

    val categories = listOf(
        Category("food", "مطاعم", Icons.Rounded.Restaurant, Color(0xFFD9733A)),
        Category("grocery", "بقالة", Icons.Rounded.LocalGroceryStore, Color(0xFF3E8E5E)),
        Category("bakery", "مخابز وحلويات", Icons.Rounded.BakeryDining, Color(0xFFB9813A)),
        Category("pharmacy", "صيدلية", Icons.Rounded.LocalPharmacy, Color(0xFF3F7CAC)),
        Category("beauty", "عطور وتجميل", Icons.Rounded.Spa, Color(0xFFB0577A)),
        Category("homefood", "أكل بيتي", Icons.Rounded.SoupKitchen, Color(0xFF8A6A3B)),
        Category("flowers", "ورد وهدايا", Icons.Rounded.LocalFlorist, Color(0xFFC85A5A)),
    )

    private val home = GeoP(33.3032, 44.4351)

    val stores = listOf(
        Store("s1", "مشويات أبو حيدر", "food", "تكة · كباب · معلاك", 4.7, 15, 1.2, 1500, GeoP(33.3101, 44.4302), Color(0xFF8C3B2E)),
        Store("s2", "بيتزا الطابوق", "food", "بيتزا على فرن الحطب", 4.5, 20, 2.1, 2000, GeoP(33.2958, 44.4219), Color(0xFFB5523B)),
        Store("s3", "فلافل الجسر", "food", "فلافل · عمبة · سمبوسة", 4.8, 8, 0.7, 1000, GeoP(33.3068, 44.4389), Color(0xFF66753A)),
        Store("s4", "أسواق النخلة", "grocery", "خضرة · ألبان · منظفات", 4.4, 10, 0.9, 1500, GeoP(33.2991, 44.4398), Color(0xFF2F6B4F)),
        Store("s5", "مخبز الصمون الحار", "bakery", "صمون حجري طازج كل ساعة", 4.9, 5, 0.5, 1000, GeoP(33.3049, 44.4322), Color(0xFFA8722F)),
        Store("s6", "حلويات الكليجة", "bakery", "كليجة · زلابية · كيك", 4.6, 10, 1.6, 1500, GeoP(33.3122, 44.4417), Color(0xFF7A4E2D)),
        Store("s7", "صيدلية الشفاء", "pharmacy", "أدوية · عناية · مستلزمات أطفال", 4.7, 5, 1.0, 1500, GeoP(33.2987, 44.4300), Color(0xFF2F5F8A)),
        Store("s8", "عطور ريحانة", "beauty", "عطور شرقية · مكياج · عناية", 4.5, 10, 2.4, 2500, GeoP(33.3175, 44.4260), Color(0xFF8A3E5E)),
        Store("s9", "مطبخ أم سجاد", "homefood", "دولمة · برياني · تشريب", 4.9, 40, 1.8, 2000, GeoP(33.2940, 44.4370), Color(0xFF6B5132)),
        Store("s10", "ورد الكرادة", "flowers", "باقات · هدايا · تغليف", 4.6, 15, 1.3, 2000, GeoP(33.3090, 44.4445), Color(0xFF9E3D46)),
    )

    val products = listOf(
        // مشويات أبو حيدر
        Product("p101", "s1", "تكة لحم", "سيخين مع خبز تنور وطماطة مشوية", 7000, "المشويات"),
        Product("p102", "s1", "كباب عراقي", "ثلاث أسياخ مع بصل وسماق", 6000, "المشويات"),
        Product("p103", "s1", "معلاك", "معلاك غنم متبّل على الفحم", 8000, "المشويات"),
        Product("p104", "s1", "لفة كباب", "كباب بخبز صاج مع عمبة", 2500, "اللفّات"),
        Product("p105", "s1", "شوربة عدس", "طاسة شوربة حارّة", 1500, "جانبي"),
        Product("p106", "s1", "لبن عيران", "قنينة باردة", 750, "مشروبات"),
        // بيتزا الطابوق
        Product("p201", "s2", "بيتزا مارگريتا", "صلصة طماطة وجبن موزاريلا · وسط", 6000, "البيتزا"),
        Product("p202", "s2", "بيتزا دجاج بالفطر", "دجاج مشوي وفطر وزيتون · وسط", 7500, "البيتزا"),
        Product("p203", "s2", "بيتزا خضار", "فلفل ملوّن وبصل وزيتون · وسط", 6500, "البيتزا"),
        Product("p204", "s2", "خبز بالثوم", "ست قطع مع صوص", 2500, "المقبلات"),
        Product("p205", "s2", "سلطة سيزر", "خس وخبز محمّص وصوص سيزر", 4000, "المقبلات"),
        // فلافل الجسر
        Product("p301", "s3", "لفة فلافل", "صمون حار مع عمبة وخضرة", 1000, "اللفّات"),
        Product("p302", "s3", "لفة فلافل دبل", "ضعف الفلافل مع بيض", 1750, "اللفّات"),
        Product("p303", "s3", "صحن فلافل", "12 حبة مع طحينية", 3000, "الصحون"),
        Product("p304", "s3", "سمبوسة جبن", "4 قطع مقرمشة", 2000, "الصحون"),
        // أسواق النخلة
        Product("p401", "s4", "طماطة", "كيلو واحد", 1000, "خضرة وفواكه"),
        Product("p402", "s4", "خيار", "كيلو واحد", 1000, "خضرة وفواكه"),
        Product("p403", "s4", "موز", "كيلو واحد", 2000, "خضرة وفواكه"),
        Product("p404", "s4", "حليب طازج", "لتر واحد", 1750, "ألبان وبيض"),
        Product("p405", "s4", "بيض", "طبقة 30 بيضة", 6000, "ألبان وبيض"),
        Product("p406", "s4", "قيمر", "علبة 250 غرام", 2500, "ألبان وبيض"),
        Product("p407", "s4", "مسحوق غسيل", "3 كيلو", 7500, "منظفات"),
        // مخبز الصمون الحار
        Product("p501", "s5", "صمون حجري", "10 صمونات طازجة", 1000, "الخبز"),
        Product("p502", "s5", "خبز تنور", "5 أرغفة", 1000, "الخبز"),
        Product("p503", "s5", "كعك بالسمسم", "نص كيلو", 3000, "المعجنات"),
        Product("p504", "s5", "فطائر جبن", "6 قطع", 3000, "المعجنات"),
        // حلويات الكليجة
        Product("p601", "s6", "كليجة بالتمر", "كيلو واحد", 9000, "الحلويات"),
        Product("p602", "s6", "زلابية", "نص كيلو", 4000, "الحلويات"),
        Product("p603", "s6", "كيك شوكولاتة", "قالب يكفي 8 أشخاص", 18000, "الكيك"),
        Product("p604", "s6", "زنود الست", "6 قطع بالقشطة", 4500, "الحلويات"),
        // صيدلية الشفاء
        Product("p701", "s7", "باراسيتامول 500", "علبة 24 حبة", 1500, "أدوية بدون وصفة"),
        Product("p702", "s7", "شراب سعال للأطفال", "100 مل", 4000, "أدوية بدون وصفة"),
        Product("p703", "s7", "معقّم يدين", "250 مل", 2500, "عناية"),
        Product("p704", "s7", "حفاضات أطفال", "مقاس 4 · 40 قطعة", 14000, "أطفال"),
        // عطور ريحانة
        Product("p801", "s8", "دهن عود", "3 مل", 25000, "العطور"),
        Product("p802", "s8", "عطر مسك أبيض", "50 مل", 15000, "العطور"),
        Product("p803", "s8", "كريم مرطّب", "100 مل", 8000, "العناية"),
        // مطبخ أم سجاد
        Product("p901", "s9", "دولمة", "صينية صغيرة تكفي 3 أشخاص", 20000, "أطباق اليوم"),
        Product("p902", "s9", "برياني دجاج", "صحن كبير مع شوربة", 9000, "أطباق اليوم"),
        Product("p903", "s9", "تشريب لحم", "طاسة مع خبز", 10000, "أطباق اليوم"),
        Product("p904", "s9", "كبة حلب", "6 قطع", 6000, "جانبي"),
        // ورد الكرادة
        Product("p1001", "s10", "باقة ورد أحمر", "12 وردة مع تغليف", 25000, "الباقات"),
        Product("p1002", "s10", "باقة ربيعية", "ورد مشكّل ملوّن", 20000, "الباقات"),
        Product("p1003", "s10", "علبة شوكولاتة هدية", "مع كارت تهنئة", 15000, "الهدايا"),
    )

    val addresses = listOf(
        Address("a1", "البيت", "الكرادة داخل - زقاق 12 - دار 7", "مقابل مخبز الصمون", home),
        Address("a2", "الدوام", "شارع السعدون - عمارة 3 - الطابق الثاني", "جنب المصرف", GeoP(33.3155, 44.4210)),
    )

    val drivers = listOf(
        Driver("مصطفى كريم", "دراجة نارية", false, 4.8),
        Driver("حيدر سلمان", "دراجة نارية", false, 4.6),
        Driver("علي جبار", "سيارة صالون", true, 4.9),
    )

    fun store(id: String): Store? = stores.firstOrNull { it.id == id }
    fun product(id: String): Product? = products.firstOrNull { it.id == id }
    fun category(id: String): Category? = categories.firstOrNull { it.id == id }
    fun productsOf(storeId: String): List<Product> = products.filter { it.storeId == storeId }

    /** بحث بأسماء المنتجات والمتاجر معاً. */
    fun search(query: String): List<Product> {
        val q = query.trim()
        if (q.isEmpty()) return emptyList()
        return products.filter { p ->
            p.name.contains(q) || p.description.contains(q) || (store(p.storeId)?.name?.contains(q) == true)
        }
    }

    private fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int): Long =
        LocalDateTime.of(year, month, day, hour, minute).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()

    private fun line(productId: String, qty: Int, priceThen: Int? = null): OrderLine {
        val p = product(productId)!!
        return OrderLine(p.id, p.name, priceThen ?: p.price, qty)
    }

    /** طلبات سابقة حتى تبين شاشة "نشاطي" مليانة. */
    val pastOrders: List<Order> = listOf(
        Order(
            "W-10482", store("s1")!!, listOf(line("p101", 2), line("p105", 2)), 1500,
            addresses[0], at(2026, 11, 8, 20, 15), OrderStatus.DELIVERED, "4821", drivers[0],
        ),
        Order(
            "W-10391", store("s5")!!, listOf(line("p501", 2), line("p504", 1)), 1000,
            addresses[0], at(2026, 11, 3, 7, 40), OrderStatus.DELIVERED, "1190", drivers[1],
        ),
        // سعر البيتزا كان أرخص، حتى "اطلب مرة ثانية" ينبّه إن السعر تغيّر
        Order(
            "W-10277", store("s2")!!, listOf(line("p202", 1, priceThen = 7000), line("p204", 1)), 2000,
            addresses[1], at(2026, 10, 27, 14, 5), OrderStatus.DELIVERED, "7302", drivers[2],
        ),
        Order(
            "W-10150", store("s7")!!, listOf(line("p701", 1), line("p703", 2)), 1500,
            addresses[0], at(2026, 10, 19, 22, 30), OrderStatus.CANCELLED, "5547", null,
        ),
        Order(
            "W-10033", store("s9")!!, listOf(line("p901", 1), line("p904", 1)), 2000,
            addresses[0], at(2026, 10, 5, 13, 0), OrderStatus.DELIVERED, "6610", drivers[0],
        ),
    )
}
