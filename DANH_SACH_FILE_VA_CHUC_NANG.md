# 🧭 BẢN ĐỒ HÀNH TRÌNH - DANH SÁCH VỊ TRÍ & CHỨC NĂNG CÁC FILE

Tài liệu này tổng hợp toàn bộ cấu trúc thư mục, vị trí và vai trò chi tiết của từng file trong dự án **Bản Đồ Hành Trình** (Flutter & Android).

---

## 📁 1. CÂY THƯ MỤC TỔNG QUAN

```text
ban-do-hanh-trinh/
├── android/                             # Mã nguồn và cấu hình nền tảng Android Native
│   ├── app/
│   │   ├── build.gradle.kts             # Cấu hình build Android (compileSdk, minSdk, dependencies)
│   │   └── src/main/
│   │       ├── AndroidManifest.xml      # Khai báo quyền (GPS, Foreground Service, Internet) & App Icon
│   │       ├── kotlin/.../MainActivity.kt # Xử lý La bàn phần cứng Native qua EventChannel
│   │       └── res/                     # Tài nguyên Android (ICON ỨNG DỤNG, theme khởi động)
│   └── build.gradle.kts                 # Cấu hình Gradle gốc & plugin Kotlin/AGP
├── lib/                                 # Toàn bộ mã nguồn ứng dụng Flutter / Dart
│   ├── main.dart                        # Điểm khởi chạy ứng dụng (Entry point)
│   ├── models/                          # Các lớp đối tượng dữ liệu (Data Models)
│   ├── providers/                       # Quản lý trạng thái (State Management / Business Logic)
│   ├── screens/                         # Các màn hình giao diện chính (UI Screens)
│   ├── services/                        # Các dịch vụ xử lý nền, API bản đồ, Database, Cảm biến
│   ├── theme/                           # Bảng màu, typography và kiểu dáng giao diện
│   └── widgets/                         # Các thành phần giao diện tái sử dụng và hộp thoại
├── test/
│   └── widget_test.dart                 # Bộ kiểm thử tự động (Unit test & Widget test)
├── pubspec.yaml                         # Quản lý thư viện phụ thuộc và metadata dự án
└── analysis_options.yaml                # Bộ quy tắc lint phân tích mã nguồn Dart
```

---

## 🎨 2. VỊ TRÍ LƯU ICON ỨNG DỤNG & CÁCH THAY ĐỔI

### 📍 Vị trí lưu trữ icon ứng dụng hiện tại:
Trong dự án Android, icon ứng dụng được lưu tại các thư mục `mipmap-*` theo các mức mật độ điểm ảnh:

```text
android/app/src/main/res/
├── mipmap-mdpi/ic_launcher.png       # Mật độ trung bình (48 x 48 px)
├── mipmap-hdpi/ic_launcher.png       # Mật độ cao (72 x 72 px)
├── mipmap-xhdpi/ic_launcher.png      # Mật độ siêu cao (96 x 96 px)
├── mipmap-xxhdpi/ic_launcher.png     # Mật độ 2x siêu cao (144 x 144 px)
└── mipmap-xxxhdpi/ic_launcher.png    # Mật độ 3x cao nhất (192 x 192 px)
```

Tên file icon được khai báo trong `android/app/src/main/AndroidManifest.xml`:
```xml
<application
    android:label="Bản Đồ Hành Trình"
    android:icon="@mipmap/ic_launcher">
```

### 💡 Cách thay đổi icon ứng dụng:

- **Cách 1 (Thay thế thủ công):** Tạo các ảnh PNG với kích thước tương ứng nêu trên rồi ghi đè vào các thư mục `mipmap-*` tương ứng.
- **Cách 2 (Khuyên dùng - Dùng thư viện `flutter_launcher_icons`):**
  1. Chuẩn bị 1 file ảnh logo vuông chất lượng cao (1024x1024 px), ví dụ lưu tại `assets/icon/app_icon.png`.
  2. Khai báo vào `pubspec.yaml`:
     ```yaml
     dev_dependencies:
       flutter_launcher_icons: ^0.13.1

     flutter_launcher_icons:
       android: "ic_launcher"
       image_path: "assets/icon/app_icon.png"
       adaptive_icon_background: "#1E293B"
       adaptive_icon_foreground: "assets/icon/app_icon.png"
     ```
  3. Chạy lệnh: `dart run flutter_launcher_icons:main`. Thư viện sẽ tự sinh toàn bộ icon các kích thước chuẩn cho Android và iOS.

---

## 📄 3. CHI TIẾT TỪNG FILE TRONG THƯ MỤC `lib/`

### 3.1. File khởi động chính
| File | Đường dẫn | Chức năng chính |
| :--- | :--- | :--- |
| **main.dart** | `lib/main.dart` | Điểm khởi chạy của ứng dụng (`runApp`). Khởi tạo `MultiProvider` (`TripProvider`, `TrackingProvider`, `MapSettingsProvider`), cấu hình `AppTheme` tối/sáng và liên kết với `MainScreen`. |

---

### 3.2. Thư mục `lib/models/` (Dữ liệu / Thực thể)
| File | Đường dẫn | Chức năng chính |
| :--- | :--- | :--- |
| **trip.dart** | `lib/models/trip.dart` | Thực thể một chuyến hành trình: ID, tiêu đề, thời gian bắt đầu/kết thúc, khoảng cách (km), vận tốc trung bình/tối đa, địa chỉ bắt đầu/kết thúc, danh sách điểm toạ độ và điểm ghé. |
| **track_point.dart** | `lib/models/track_point.dart` | Toạ độ GPS đơn lẻ trong lộ trình di chuyển: vĩ độ, kinh độ, độ cao, vận tốc tại thời điểm đó, dấu thời gian (timestamp). |
| **stay_point.dart** | `lib/models/stay_point.dart` | Điểm dừng chân / lưu trú (tự động phát hiện khi đứng yên >= 15 phút): vị trí, bán kính, thời gian bắt đầu/kết thúc dừng, ghi chú check-in. |
| **waypoint.dart** | `lib/models/waypoint.dart` | Điểm đánh dấu do người dùng chủ động check-in trên đường: toạ độ, tên địa điểm, ghi chú, ảnh đính kèm. |
| **vehicle_type.dart** | `lib/models/vehicle_type.dart` | Định nghĩa enum các loại phương tiện (Xe máy, Ô tô, Xe đạp, Đi bộ, Xe điện, Xe khách, Mũi tên), bảng màu hiển thị và các hàm lấy icon, góc quay. |
| **province_stats.dart** | `lib/models/province_stats.dart` | Dữ liệu thống kê mức độ khám phá theo từng tỉnh/thành phố tại Việt Nam: tên tỉnh, số chuyến đã qua, số km đã đi, điểm đánh giá. |
| **monthly_stats.dart** | `lib/models/monthly_stats.dart` | Dữ liệu tổng hợp theo tháng: tổng km, số chuyến, thời lượng di chuyển, biểu đồ quãng đường từng ngày trong tháng. |

---

### 3.3. Thư mục `lib/providers/` (Quản lý trạng thái & Logic nghiệp vụ)
| File | Đường dẫn | Chức năng chính |
| :--- | :--- | :--- |
| **tracking_provider.dart** | `lib/providers/tracking_provider.dart` | Quản lý việc ghi lại hành trình thời gian thực: lắng nghe GPS từ `LocationService`, phát hiện dừng >= 15 phút, tính toán quãng đường, vận tốc, tự nhận diện điểm **"Nhà"** (`isNearHome`) khi xuất phát hoặc về đích. |
| **trip_provider.dart** | `lib/providers/trip_provider.dart` | Quản lý danh sách lịch sử chuyến đi: tải danh sách từ SQLite, xóa chuyến, đổi tên, tính toán thống kê bảng xếp hạng tỉnh thành và tháng. |
| **map_settings_provider.dart** | `lib/providers/map_settings_provider.dart` | Quản lý và lưu trữ cài đặt bản đồ vào `SharedPreferences`: loại bản đồ (Google Maps, OpenMap.vn, OpenStreetMap, VietMap...), API key, cấu hình toạ độ/bán kính ghim **"Nhà"**, loại phương tiện, màu sắc, và tùy chọn xoay bản đồ theo hướng di chuyển. |

---

### 3.4. Thư mục `lib/screens/` (Màn hình giao diện)
| File | Đường dẫn | Chức năng chính |
| :--- | :--- | :--- |
| **main_screen.dart** | `lib/screens/main_screen.dart` | Màn hình khung điều hướng chính chứa thanh BottomNavigationBar (4 tab: Khám Phá, Bản Đồ, Thống Kê, Lịch Sử) + AppBar với lối tắt vào Cài đặt, Bảng xếp hạng, Album ảnh. |
| **discovery_map_screen.dart** | `lib/screens/discovery_map_screen.dart` | Tab 2 "Bản Đồ": Bản đồ khám phá tổng hợp toàn bộ các cung đường đã đi (dạng thắp sáng bản đồ / Fog of War), danh hiệu nhà thám hiểm, danh sách lớp phủ. |
| **trips_history_screen.dart** | `lib/screens/trips_history_screen.dart` | Tab 4 "Lịch Sử": Danh sách toàn bộ các chuyến đi đã lưu, hỗ trợ tìm kiếm, lọc, hiển thị thẻ chuyến đi kèm badge "Xuất phát từ Nhà / Về Nhà", banner lời nhắn bạn đồng hành. |
| **trip_detail_screen.dart** | `lib/screens/trip_detail_screen.dart` | Màn hình chi tiết một chuyến đi: xem lại toàn bộ cung đường, cờ xuất phát/kết thúc, thanh tua tua nhanh lộ trình (scrubber) theo thời gian, đo vận tốc và độ cao. |
| **monthly_stats_screen.dart** | `lib/screens/monthly_stats_screen.dart` | Tab 3 "Thống Kê": Thống kê theo tháng, biểu đồ cột tương tác ngày kỷ lục cao nhất, lời nhắn phân tích thành tích cá nhân. |
| **province_ranking_screen.dart** | `lib/screens/province_ranking_screen.dart` | Màn hình Bảng xếp hạng Tỉnh/Thành: hiển thị tiến độ mở khóa 63 tỉnh thành Việt Nam, danh hiệu, các ghi chú thân thiện cho tỉnh đi nhiều nhất hoặc quê hương. |
| **photo_discovery_screen.dart** | `lib/screens/photo_discovery_screen.dart` | Màn hình Khám phá qua Thư viện ảnh: quét tọa độ GPS từ ảnh chụp EXIF trong máy điện thoại để ghim lên bản đồ những nơi người dùng đã từng chụp ảnh. |
| **settings_screen.dart** | `lib/screens/settings_screen.dart` | Màn hình Cài Đặt hoàn chỉnh: chọn nguồn bản đồ, nhập API Key, cấu hình ghim vị trí "Nhà", tùy chọn biểu tượng phương tiện và la bàn, sao lưu dữ liệu. |

---

### 3.5. Thư mục `lib/services/` (Dịch vụ nền & Hạ tầng)
| File | Đường dẫn | Chức năng chính |
| :--- | :--- | :--- |
| **location_service.dart** | `lib/services/location_service.dart` | Giao tiếp phần cứng GPS: xin cấp quyền vị trí, lấy toạ độ ban đầu, luồng stream vị trí khi chờ (idle) và theo dõi liên tục ở chế độ nền (background tracking). |
| **compass_service.dart** | `lib/services/compass_service.dart` | Quản lý cảm biến La bàn: kết nối với kênh Android Native `EventChannel("trluc.top/compass")`, lọc và làm mượt góc quay (`smoothHeading`), tự dừng khi app xuống nền. |
| **database_service.dart** | `lib/services/database_service.dart` | Cơ sở dữ liệu cục bộ SQLite (`sqflite`): tạo bảng, lưu trữ chuyến đi, các điểm GPS, điểm ghé, điểm dừng chân, tối ưu truy vấn offline. |
| **companion_quotes.dart** | `lib/services/companion_quotes.dart` | Bộ sinh lời nhắn bạn đồng hành ngẫu nhiên thông minh dựa trên dữ liệu thật (lời chào mở app, nhận xét quê hương, chúc mừng kỷ lục tháng, v.v.). |
| **nearby_places_service.dart** | `lib/services/nearby_places_service.dart` | Tìm kiếm các địa điểm xung quanh toạ độ hiện tại qua OpenStreetMap Overpass API để người dùng chọn tên check-in nhanh không cần gõ phím. |
| **photo_discovery_service.dart** | `lib/services/photo_discovery_service.dart` | Quét ảnh từ thiết bị, đọc siêu dữ liệu EXIF lấy toạ độ GPS và thời gian chụp ảnh để hiển thị lên bản đồ. |
| **openmap_service.dart** | `lib/services/openmap_service.dart` | Tích hợp dịch vụ OpenMap.vn / NDAMaps: Reverse Geocoding (chuyển toạ độ thành địa chỉ tiếng Việt), tìm kiếm địa điểm. |
| **goong_service.dart** | `lib/services/goong_service.dart` | Tích hợp Goong REST API: Geocoding chuyển đổi địa chỉ và địa danh Việt Nam. |
| **external_map_service.dart** | `lib/services/external_map_service.dart` | Mở toạ độ hoặc lộ trình sang ứng dụng bản đồ bên ngoài (Google Maps, Apple Maps). |
| **offline_map_service.dart** | `lib/services/offline_map_service.dart` | Tải trước các mảnh bản đồ (tile preloading) để sử dụng mượt mà khi không có kết nối Internet. |

---

### 3.6. Thư mục `lib/widgets/` (Thành phần giao diện tái sử dụng)
| File | Đường dẫn | Chức năng chính |
| :--- | :--- | :--- |
| **goong_map_widget.dart** | `lib/widgets/goong_map_widget.dart` | Widget bản đồ trung tâm (dùng `flutter_map`): xử lý hiển thị tile đa nguồn, vẽ line lộ trình neon, điểm đánh dấu, tự động zoom vị trí hiện tại khi mở app, xoay bản đồ theo hướng xe chạy, hỗ trợ nhấn giữ để ghim "Nhà". |
| **user_location_marker.dart** | `lib/widgets/user_location_marker.dart` | Marker biểu tượng người dùng / phương tiện: hiển thị chùm tia la bàn chỉ hướng điện thoại, huy hiệu phương tiện khi di chuyển, và marker ghim "Nhà" kèm vòng tròn bán kính. |
| **vehicle_picker_sheet.dart** | `lib/widgets/vehicle_picker_sheet.dart` | Hộp thoại dưới (bottom sheet) chọn nhanh loại phương tiện di chuyển, đổi màu sắc và bật/tắt xoay bản đồ theo hướng xe chạy. |
| **home_picker_dialog.dart** | `lib/widgets/home_picker_dialog.dart` | Hộp thoại chọn toạ độ "Nhà" trực quan trên bản đồ kèm các mức bán kính nhận diện (100m, 200m, 300m, 500m). |
| **pending_stay_dialog.dart** | `lib/widgets/pending_stay_dialog.dart` | Hộp thoại thông báo phát hiện điểm dừng >= 15 phút: tích hợp danh sách địa điểm xung quanh để chọn nhanh làm tên điểm check-in. |
| **place_picker_map_widget.dart** | `lib/widgets/place_picker_map_widget.dart` | Widget bản đồ thu nhỏ hỗ trợ người dùng chọn vị trí toạ độ trực quan bằng cách di chuyển tâm ngắm. |
| **vector_map_style_mixin.dart** | `lib/widgets/vector_map_style_mixin.dart` | Mixin cung cấp cấu hình URL bản đồ, vector style (NDAMaps) và tile raster (Google Maps, OSM, Carto). |
| **smart_tile_provider.dart** | `lib/widgets/smart_tile_provider.dart` | Bộ nạp tile thông minh kết hợp cache offline và fallback tự động sang bản đồ dự phòng khi mất mạng. |
| **trip_card.dart** | `lib/widgets/trip_card.dart` | Thẻ hiển thị tóm tắt thông tin một chuyến đi trong danh sách lịch sử, gắn huy hiệu "Xuất phát từ Nhà / Về Nhà". |
| **metric_card.dart** | `lib/widgets/metric_card.dart` | Thẻ hiển thị chỉ số (quãng đường, thời gian, vận tốc) với icon đẹp mắt. |
| **monthly_bar_chart.dart** | `lib/widgets/monthly_bar_chart.dart` | Biểu đồ cột thể hiện quãng đường đi của từng ngày trong tháng bằng `fl_chart`. |
| **add_waypoint_dialog.dart** | `lib/widgets/add_waypoint_dialog.dart` | Hộp thoại thêm điểm đánh dấu / điểm ghé thủ công trong khi đang ghi hành trình. |
| **offline_map_preload_dialog.dart** | `lib/widgets/offline_map_preload_dialog.dart` | Hộp thoại chọn khu vực và mức zoom để tải trước bản đồ offline. |

---

### 3.7. Thư mục `lib/theme/` (Giao diện & Chủ đề)
| File | Đường dẫn | Chức năng chính |
| :--- | :--- | :--- |
| **app_theme.dart** | `lib/theme/app_theme.dart` | Khai báo bảng màu sắc chủ đạo (Teal khám phá, Slate tối, Amber điểm nhấn), font chữ, kiểu bo góc và cấu hình `ThemeData` sáng/tối đồng nhất cho toàn bộ app. |

---

## 🤖 4. MÃ NGUỒN ANDROID NATIVE & CẤU HÌNH HỆ THỐNG

| File | Đường dẫn | Chức năng chính |
| :--- | :--- | :--- |
| **MainActivity.kt** | `android/app/src/main/kotlin/trluc/top/ban_do_hanh_trinh/MainActivity.kt` | Mã nguồn Kotlin chạy trực tiếp trên Android: Đăng ký `EventChannel("trluc.top/compass")` để lấy dữ liệu phần cứng `Sensor.TYPE_ROTATION_VECTOR`, tự động tính toán bù trừ góc xoay màn hình điện thoại (0°, 90°, 180°, 270°) và gửi góc la bàn mượt về Flutter. |
| **AndroidManifest.xml** | `android/app/src/main/AndroidManifest.xml` | Khai báo quyền hệ điều hành: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`, `INTERNET`, cấu hình Icon ứng dụng và Activity khởi động. |
| **build.gradle.kts (app)** | `android/app/build.gradle.kts` | Cấu hình cấp ứng dụng Android: `compileSdk = 36`, `minSdk = 21`, `targetSdk = 36`, `applicationId = "trluc.top.ban_do_hanh_trinh"`, Java 17, và mã hóa build release. |
| **build.gradle.kts (root)** | `android/build.gradle.kts` | Cấu hình cấp dự án Android: Plugin Android Gradle Plugin (AGP 9.1.0) và Kotlin. |

---

## 🧪 5. KIỂM THỬ TỰ ĐỘNG & QUẢN LÝ THƯ VIỆN

| File | Đường dẫn | Chức năng chính |
| :--- | :--- | :--- |
| **widget_test.dart** | `test/widget_test.dart` | Tập hợp 15 bài kiểm thử tự động (Unit Test & Integration Test) kiểm tra toàn bộ luồng: format thời gian, tính toán khoảng cách GPS, logic nhận diện vị trí "Nhà", làm mượt góc xoay la bàn, bộ sinh lời nhắn bạn đồng hành, v.v. |
| **pubspec.yaml** | `pubspec.yaml` | Quản lý tên app, phiên bản (`1.0.0+1`), các thư viện bên thứ 3 (`flutter_map`, `geolocator`, `provider`, `sqflite`, `fl_chart`, `exif`, v.v.) và tài nguyên hình ảnh. |
