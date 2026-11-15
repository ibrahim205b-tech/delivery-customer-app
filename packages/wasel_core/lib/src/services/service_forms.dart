/// حقول طلب كل خدمة. الطلب العام يعرض هذه الحقول للزبون، ثم يرسلها كما هي للمقدم.
/// هذه أسماء الحقول وأنواعها فقط، لا أسعار ولا شروط تجارية.
enum ServiceFormKind { text, number, choice, date }

class ServiceFormField {
  final String key;
  final String label;
  final ServiceFormKind kind;
  final bool required;
  final List<String> options;
  const ServiceFormField(this.key, this.label, this.kind, {this.required = false, this.options = const []});
}

const _notes = ServiceFormField('notes', 'ملاحظات', ServiceFormKind.text);

const kServiceForms = <String, List<ServiceFormField>>{
  'photographers': [
    ServiceFormField('type', 'نوع التصوير', ServiceFormKind.choice, required: true, options: ['عرس', 'مباراة', 'منتجات', 'جلسة شخصية', 'فيديو ومونتاج']),
    ServiceFormField('date', 'التاريخ', ServiceFormKind.date, required: true),
    ServiceFormField('hours', 'عدد الساعات', ServiceFormKind.number),
    _notes,
  ],
  'clothing_store': [
    ServiceFormField('item', 'نوع القطعة', ServiceFormKind.choice, required: true, options: ['رجالي', 'نسائي', 'أطفال', 'أحذية', 'حقائب', 'إكسسوارات']),
    ServiceFormField('size', 'المقاس', ServiceFormKind.text, required: true),
    ServiceFormField('color', 'اللون', ServiceFormKind.text),
    ServiceFormField('qty', 'الكمية', ServiceFormKind.number),
    _notes,
  ],
  'device_installments': [
    ServiceFormField('device', 'الجهاز المطلوب', ServiceFormKind.text, required: true),
    ServiceFormField('down_payment', 'الدفعة المقدمة التي تقدر عليها', ServiceFormKind.number),
    ServiceFormField('months', 'عدد الأشهر المفضل', ServiceFormKind.number),
    _notes,
  ],
  'print_custom': [
    ServiceFormField('garment', 'نوع الملابس', ServiceFormKind.choice, required: true, options: ['تيشيرت', 'كاب', 'هودي', 'حقيبة', 'أخرى']),
    ServiceFormField('color', 'اللون', ServiceFormKind.text),
    ServiceFormField('size', 'المقاس', ServiceFormKind.text),
    ServiceFormField('qty', 'الكمية', ServiceFormKind.number, required: true),
    _notes,
  ],
  'phone_repair': [
    ServiceFormField('model', 'موديل الهاتف', ServiceFormKind.text, required: true),
    ServiceFormField('fault', 'العطل', ServiceFormKind.text, required: true),
    _notes,
  ],
  'carpet_cleaning': [
    ServiceFormField('item', 'نوع الشيء', ServiceFormKind.choice, required: true, options: ['فرشة', 'سجادة', 'كنب', 'ستائر']),
    ServiceFormField('count', 'عدد القطع', ServiceFormKind.number, required: true),
    ServiceFormField('size', 'المقاس', ServiceFormKind.text),
    _notes,
  ],
  'institute_seats': [
    ServiceFormField('course', 'الدورة أو المادة', ServiceFormKind.text, required: true),
    ServiceFormField('seats', 'عدد المقاعد', ServiceFormKind.number),
    _notes,
  ],
  'documents': [
    ServiceFormField('document', 'نوع المستمسك أو المعاملة', ServiceFormKind.text, required: true),
    ServiceFormField('copies', 'عدد النسخ', ServiceFormKind.number),
    _notes,
  ],
  'ps_rental': [
    ServiceFormField('device', 'نوع الجهاز', ServiceFormKind.choice, required: true, options: ['PlayStation 4', 'PlayStation 5', 'أخرى']),
    ServiceFormField('days', 'عدد الأيام', ServiceFormKind.number, required: true),
    _notes,
  ],
  'heavy_transport': [
    ServiceFormField('vehicle', 'نوع المركبة', ServiceFormKind.choice, required: true, options: ['كيا حمل', 'ستوت']),
    ServiceFormField('from', 'نقطة الاستلام', ServiceFormKind.text, required: true),
    ServiceFormField('to', 'نقطة التسليم', ServiceFormKind.text, required: true),
    ServiceFormField('load', 'وصف الحمولة', ServiceFormKind.text, required: true),
    ServiceFormField('floors', 'عدد الطوابق', ServiceFormKind.number),
    _notes,
  ],
  'travel_campaigns': [
    ServiceFormField('destination', 'الوجهة', ServiceFormKind.text, required: true),
    ServiceFormField('date', 'تاريخ الانطلاق', ServiceFormKind.date, required: true),
    ServiceFormField('seats', 'عدد الأشخاص', ServiceFormKind.number, required: true),
    _notes,
  ],
  'doctor_booking': [
    ServiceFormField('specialty', 'التخصص', ServiceFormKind.text, required: true),
    ServiceFormField('visit', 'نوع الحجز', ServiceFormKind.choice, options: ['حجز موعد', 'حجز دور حضوري']),
    _notes,
  ],
  'restaurant_booking': [
    ServiceFormField('people', 'عدد الأشخاص', ServiceFormKind.number, required: true),
    ServiceFormField('time', 'وقت الوصول', ServiceFormKind.text, required: true),
    ServiceFormField('menu', 'الطلب المسبق', ServiceFormKind.text),
    _notes,
  ],
};

/// أسماء الخدمات بالعربية (لعرض الطلب عند مقدم الخدمة)
const kServiceNames = <String, String>{
  'photographers': 'حجز مصور',
  'clothing_store': 'سوق الملابس',
  'device_installments': 'الأجهزة بالتقسيط',
  'print_custom': 'الطباعة حسب الطلب',
  'phone_repair': 'صيانة الموبايلات',
  'carpet_cleaning': 'غسل الفرشات',
  'institute_seats': 'حجز مقاعد معهد',
  'documents': 'معاملاتك علينا',
  'ps_rental': 'تأجير البلايستيشن',
  'heavy_transport': 'كيا الحمل والستوت',
  'travel_campaigns': 'السفر والسياحة',
  'doctor_booking': 'حجز طبيب',
  'restaurant_booking': 'حجز مطعم أو صالة',
  'pitch_booking': 'حجز ملعب خماسي',
};
