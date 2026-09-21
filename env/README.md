# env/ — cấu hình Firebase client theo môi trường

Mỗi môi trường (dev, pilot, prod) dùng MỘT dự án Firebase riêng. Sao chép
`<env>.example.json` thành `<env>.json`, điền giá trị công khai của dự án Firebase
tương ứng (API key/App ID/Web client ID — KHÔNG phải bí mật, nhưng `<env>.json`
vẫn bị git bỏ qua). Tuyệt đối KHÔNG đặt service account / khoá Admin ở đây.

```
flutter run --flavor dev   --dart-define-from-file=env/dev.json
flutter build apk --flavor pilot --dart-define-from-file=env/pilot.json
flutter build appbundle --flavor prod --dart-define-from-file=env/prod.json
```

Thiếu file/giá trị mẫu ⇒ Auth hiển thị "chưa cấu hình", app local vẫn chạy.
`applicationId`: dev=`com.vinhamimh.vi_nha_minh.dev`, pilot=`...pilot`,
prod=`com.vinhamimh.vi_nha_minh` (không đổi). Đăng ký SHA-1 của keystore dùng để
ký từng flavor trong Firebase Console cho đúng applicationId đó.
