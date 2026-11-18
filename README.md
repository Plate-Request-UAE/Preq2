# موقع طلب رقم مركبة مميز

| الصفحة | الملف |
|---|---|
| واجهة المراجع | `index.html` |
| لوحة الموظفات | `staff.html` |
| باركود للطباعة | `qr.html` |
| إعداد قاعدة البيانات | `supabase/schema.sql` |

## النشر (مرة وحدة)

**أ) قاعدة البيانات (Supabase)**
1. أنشئ مشروع جديد باسمك في supabase.com.
2. من SQL Editor شغّل محتوى `supabase/schema.sql`.
3. من Project Settings → API انسخ **Project URL** و**anon public key**، وضعهم في أول ملف `sb.js` مكان `SB_URL` و`SB_KEY`.
4. أنشئ حساب لكل موظفة: Authentication → Add user بإيميل `<الاسم>@plate-demo.local` وكلمة مرور قوية، ثم في SQL:
   `insert into public.staff(user_id, username) select id, '<الاسم>' from auth.users where email='<الاسم>@plate-demo.local';`

**ب) الموقع (GitHub Pages)**
1. أنشئ مستودع جديد في github.com وارفع ملفات هذا المجلد (`index.html` و`staff.html` و`qr.html` و`sb.js`).
2. Settings → Pages → اختر branch `main` ثم Save.
3. بعد دقيقة يظهر رابط الموقع: `https://اسمك.github.io/اسم-المستودع/`.
4. افتح `qr.html` من الرابط واطبع الباركود (فيه زر طباعة).

## ملاحظات
- مشاريع Supabase المجانية تتوقف بعد أسبوع بلا استخدام، وتُعاد من لوحة Supabase بزر Restore.
- لا تضع كلمات مرور الموظفات في المستودع.
