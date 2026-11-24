# 🗺️ Bản Đồ Hành Trình (Journey Discovery & Fog of War)

Ứng dụng di động Flutter (Android) giúp ghi lại lịch sử di chuyển, khám phá bản đồ thực tế theo cơ chế mở sương mù (**Fog of War**), tính toán chính xác số kilomet đường mới không trùng lặp, mở khóa 63 tỉnh/thành Việt Nam, gom bộ sưu tập ảnh theo địa điểm, tự động nhận diện chuyến đi chạy ngầm và hỗ trợ cập nhật ứng dụng tự động qua GitHub Releases.

> [!NOTE]
> Ứng dụng hoạt động với kiến trúc đa nguồn bản đồ trực tiếp (**Google Maps**, **OpenMap.vn / NDAMaps Vector**, **OpenStreetMap**, **ESRI**, **Offline Maps**)

---

## 🌟 Tính Năng Nổi Bật

### 1. Bản Đồ Hợp Nhất & Giao Diện Ghi Hành Trình Tối Giản
- **Nút tròn Play / Stop**: Thao tác bắt đầu và kết thúc ghi chuyến đi nhanh chóng chỉ với 1 chạm.
- **Nút tròn chọn phương tiện**: Đổi biểu tượng phương tiện linh hoạt (mặc định là **Xe máy**, hỗ trợ **Ô tô**, **Xe đạp**, **Đi bộ**, **Chạy bộ**, **Tàu hỏa**, **Thuyền**, **Mũi tên**).
- **Ẩn / hiện ghim thông minh**: Khi bắt đầu di chuyển, toàn bộ ghim check-in và ảnh trên bản đồ tự động ẩn đi để tầm nhìn thông thoáng; khi dừng ghi sẽ tự động hiển thị trở lại.
- **Vẽ polyline & đếm km thời gian thực**: Đường đi liên tục được vẽ trực tiếp lên bản đồ ngay khi xe lăn bánh, cập nhật đồng thời chỉ số *Đã khám phá (mới)* và *Tổng đi*.
- **Tối ưu tiết kiệm pin**: Tự động ngắt lắng nghe GPS nền liên tục khi đang nghỉ/không ghi hành trình (chỉ kích hoạt định vị 1 lần khi người dùng bấm nút căn giữa vị trí).

### 2. Ghi Nhận Phương Tiện Từng Chặng & Tua Lại Theo Thời Điểm
- Cho phép đổi phương tiện ngay giữa chuyến đi (ví dụ: `Xe máy → Ô tô`).
- Lịch sử chuyến đi ghi nhận chi tiết chuỗi phương tiện đã sử dụng.
- **Thanh tua lại lộ trình (Interactive Scrubber)** trong màn hình chi tiết chuyến đi: Biểu tượng phương tiện trên bản đồ tự động thay đổi đúng loại phương tiện tại từng mốc thời gian.

### 3. Thuật Toán Tính Km Khám Phá Thực Tế (Không Trùng Lặp)
- Ứng dụng thuật toán lưới băm không gian **`ExplorationIndex`** (sai số làn đường 25m, chia nhỏ phân đoạn 20m, trễ góc cua 60m).
- Khi người dùng đi lại trên cung đường cũ (đi về trong ngày hoặc đi lại tuyến đường quen thuộc), hệ thống chỉ tính km khám phá mới cho những đoạn đường **thực sự lần đầu đặt chân tới**.
- Màn hình chi tiết chuyến đi phân màu trực quan: **Đoạn đường Mới** (Xanh Neon) vs **Đoạn đường Đã Đi** (Tím nhạt).

### 4. Theo Dõi Chạy Ngầm & Tự Động Tạo Chuyến Đi
- Thuật toán **`AutoTripDetector`** phân tích tốc độ duy trì, độ dịch chuyển ròng và tỷ lệ hướng thẳng nhằm chống nhiễu GPS khi đứng yên hoặc đi lại quanh nhà/văn phòng.
- Tự động bắt đầu ghi chuyến đi mới khi phát hiện người dùng thực sự di chuyển tốc độ cao bằng phương tiện giao thông.
- Tự động kết thúc chuyến đi khi người dùng dừng chân lâu.
- Tự động phát hiện điểm dừng chân `>= 2 phút` và gợi ý địa danh xung quanh để check-in 1 chạm.

### 5. Ghim Địa Điểm Thông Minh & Tìm Kiếm Từ Xa
- **Ghim vị trí "Nhà"**: Bán kính nhận diện 50m, tự động nhận diện xuất phát hoặc kết thúc tại Nhà.
- **Ghim đa danh mục**: Công ty, Trường học, Quán quen, Quán ăn, Tham quan, Bãi xe, Điểm yêu thích.
- **Tìm kiếm từ xa**: Tìm kiếm địa điểm theo tên, địa chỉ hoặc toạ độ GPS (hỗ trợ OpenMap, Google Geocoding, OSM Nominatim và dữ liệu 63 tỉnh offline) để ghim trước mà không cần đang có mặt tại địa điểm đó.

### 6. Mở Khóa & Xếp Hạng 63 Tỉnh/Thành Việt Nam
- Bộ toạ độ tham chiếu ngoại tuyến 63 tỉnh/thành (`VietnamProvinces.provinceForCoordinate`).
- **Phân bổ km cho mọi tỉnh đi qua**: Các chuyến đi xuyên tỉnh (ví dụ từ TP. Hồ Chí Minh đi Lâm Đồng qua Bình Dương, Đồng Nai) sẽ tự động chia nhỏ từng mét đường và cộng số km/chuyến đi cho **toàn bộ các tỉnh trên lộ trình**.
- Cấp bậc khám phá theo cự ly từng tỉnh: *Mới Đặt Chân*, *Đã Ghé Thăm*, *Khám Phá Sâu*, *Khám Phá Toàn Diện*.

### 7. Bộ Sưu Tập Ảnh Gom Thư Mục Theo Địa Điểm
- Đọc toạ độ GPS nguyên bản từ thẻ EXIF của file ảnh chụp hoặc qua Google Photos.
- **Gom thư mục tự động**: Các ảnh có cùng tên địa điểm hoặc chụp gần toạ độ nhau (`<= 250m`) được tự động gom chung vào một thư mục địa danh.
- Không hiển thị bản đồ trong tab Ảnh để tối ưu tốc độ cuộn và tập trung vào trải nghiệm bộ sưu tập.

### 8. Đa Nguồn Bản Đồ & Bản Đồ Ngoại Tuyến (Offline)
- **Google Maps**: Bản đồ đường phố tiếng Việt chuẩn, Vệ tinh lai (Hybrid), Vệ tinh thuần, Địa hình.
- **OpenMap.vn / NDAMaps (Vector Tiles)**: Giao diện ban ngày (`day-v1`), ban đêm (`night-v1`), vệ tinh (`satellite-v1`).
- **OpenStreetMap**: Bản đồ OSM chuẩn quốc tế & OSM HOT tiếng Việt.
- **ESRI World Imagery & OpenTopoMap**: Ảnh vệ tinh độ phân giải cao và địa hình trực quan.
- **Tải trước bản đồ ngoại tuyến**: Lưu trữ các mảnh bản đồ theo bán kính hoặc theo Tỉnh/Thành, tự động đọc cache khi mất kết nối mạng.

### 9. Cập Nhật Ứng Dụng Tự Động (GitHub Releases)
- Tích hợp kiểm tra phiên bản mới qua GitHub API (hỗ trợ cả kho lưu trữ công khai và riêng tư thông qua GitHub Personal Access Token).
- Tải trực tiếp file APK có thanh tiến trình % và kích hoạt trình cài đặt hệ thống Android.

---

## 📱 Cấu Trúc Điều Hướng (5 Tabs)

| Tab | Tên Màn Hình | Chức Năng Chính |
| :--- | :--- | :--- |
| **1** | **Bản Đồ** | Bản đồ trung tâm, nút tròn Play/Stop ghi hành trình, chọn xe, vẽ lộ trình trực tiếp, HUD thời gian thực |
| **2** | **Khám Phá** | Bảng xếp hạng 63 Tỉnh/Thành Việt Nam, thống kê số km và số chuyến đi qua từng tỉnh |
| **3** | **Ảnh** | Thư mục ảnh khám phá gộp theo địa danh & toạ độ chụp gần nhau, mở Google Photos |
| **4** | **Thống Kê** | Thống kê khám phá theo tháng, biểu đồ cột ngày di chuyển, chỉ số tổng km và km mới |
| **5** | **Lịch Sử** | Danh sách hành trình đã lưu, tìm kiếm chuyến đi, xem lại chi tiết & tua lại theo thời gian |

---

## 🛠 Hướng Dẫn Cài Đặt & Phát Triển

### Yêu Cầu Môi Trường
- **Flutter SDK**: 3.13+ (Khuyên dùng Flutter 3.29+ / Dart 3.7+)
- **Android Studio / Android SDK**: `minSdkVersion = 21`, `compileSdkVersion = 36`, `targetSdkVersion = 35`
- **Java**: JDK 17 hoặc JDK 21 (Gradle 9.x)

### Các Lệnh Cơ Bản

```bash
# 1. Tải các gói thư viện phụ thuộc
flutter pub get

# 2. Kiểm tra phân tích mã nguồn
flutter analyze --no-fatal-infos

# 3. Chạy toàn bộ 26 unit test tự động
flutter test

# 4. Chạy ứng dụng trên thiết bị Android
flutter run

# 5. Đóng gói tệp APK bản phát hành
flutter build apk --release
```

*Tệp APK sau khi đóng gói sẽ nằm tại: `build/app/outputs/flutter-apk/app-release.apk`.*

---

## ⚙️ Cài Đặt & Cấu Hình Bản Đồ

Trong ứng dụng, nhấn vào biểu tượng bánh răng **Cài đặt** (hiển thị trên thanh tiêu đề của mọi tab) để cấu hình:
1. **Nguồn bản đồ & Kiểu hiển thị**: Chọn Google Maps (Đường phố/Vệ tinh lai), OpenMap.vn / NDAMaps (Vector Ngày/Đêm), hoặc OpenStreetMap.
2. **API Keys (Tuỳ chọn)**:
   - *Google Geocoding API Key*: Để dịch ngược địa chỉ bằng dịch vụ Google.
   - *OpenMap / NDAMaps API Key*: Để tải vector tiles và tìm kiếm địa chỉ tiếng Việt qua OpenMap.vn.
   *(Nếu không nhập key, ứng dụng vẫn hoạt động bình thường với Google Maps Tile tiêu chuẩn, OpenStreetMap và Geocoding ngoại tuyến 63 tỉnh).*
3. **Biểu tượng & La bàn**: Chọn phương tiện mặc định, màu xe và công tắc xoay bản đồ theo hướng di chuyển/la bàn điện thoại.
4. **Vị trí "Nhà" & Chạy ngầm**: Đặt toạ độ nhà, bán kính nhận diện, bật/tắt tự động ghi hành trình khi di chuyển tốc độ cao.
5. **Cập nhật ứng dụng**: Nhập GitHub Token (nếu dùng private repo) và kiểm tra cập nhật APK mới.
