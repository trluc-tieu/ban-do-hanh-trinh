# Bản Đồ Hành Trình & Khám Phá (Goong Map Edition)

Ứng dụng Android giúp ghi lại lịch sử vị trí, vẽ bản đồ khám phá thế giới (Fog of War), thống kê số lượng và cự ly khám phá theo từng tháng, xem lại các cung đường và điểm đến chi tiết trên nền **Goong Map API**.

---

## 🌟 Tính Năng Chính

1. **Ghi lại hành trình ("Bắt đầu"):**
   - Nút "Bắt đầu hành trình" trên bản đồ Goong Map.
   - Bảng điều khiển trực tiếp (HUD): Quãng đường (km), thời gian di chuyển, tốc độ hiện tại (km/h), tốc độ trung bình.
   - Hỗ trợ "Tạm dừng", "Tiếp tục", "Đánh dấu điểm đến (Check-in/POI)", "Kết thúc & Lưu".
   - Tự động dịch ngược toạ độ xuất phát và kết thúc sang địa chỉ tiếng Việt qua Goong Geocoding API.

2. **Bản đồ khám phá (Discovery Map / Fog of War):**
   - Tổng hợp toàn bộ các cung đường đã đi qua trong lịch sử lên một bản đồ thống nhất với đường viền sáng Neon rực rỡ.
   - Hiển thị các điểm đến, danh lam thắng cảnh, quán xá đã check-in.
   - Hệ thống cấp bậc nhà thám hiểm (Tân Binh Khám Phá, Nhà Du Hành Phố Thị, Phượt Thủ Dày Dạn, Bậc Thầy Cung Đường, Huyền Thoại Khám Phá).

3. **Thống kê khám phá mỗi tháng:**
   - Bộ chọn tháng linh hoạt (`< Tháng 11/2026 >`).
   - Tổng cự ly (km), số chuyến đi, tổng thời gian khám phá, vận tốc trung bình, số điểm dừng.
   - Biểu đồ cột trực quan (`fl_chart`) thể hiện quãng đường khám phá của từng ngày trong tháng và làm nổi bật ngày kỷ lục cao nhất.
   - Danh sách toàn bộ các chuyến đi diễn ra trong tháng.

4. **Xem lại các cung đường & điểm đã đến:**
   - Lọc và tìm kiếm danh sách các chuyến đi.
   - Màn hình chi tiết chuyến đi với bản đồ Goong Map: cờ xuất phát (Xanh), cờ kết thúc (Đỏ), các điểm dừng (Vàng).
   - Thanh trượt tua hành trình (Interactive Scrubber) để xem vị trí xe/người tại từng mốc thời gian, vận tốc tương ứng và độ cao.
   - Đổi tên hành trình hoặc xoá chuyến đi.

5. **Tích hợp Goong Map API:**
   - Đầy đủ các kiểu bản đồ: Goong Map Tiêu Chuẩn, Goong Chế Độ Tối (Dark), Goong Vệ Tinh (Satellite), Goong Sáng (Light).
   - Tự động chuyển đổi bản đồ dự phòng (OpenStreetMap) khi chưa có API Key.
   - Dễ dàng cấu hình Goong MapTiles Key & REST API Key trong màn hình Cài đặt.

---

## 🛠 Hướng Dẫn Cài Đặt & Chạy

### Yêu cầu môi trường:
- Flutter SDK 3.13+ (hoặc Flutter 3.47+)
- Android Studio / Android SDK (API level 21 trở lên)

### Các lệnh chạy:
```bash
# 1. Tải các gói phụ thuộc
flutter pub get

# 2. Chạy ứng dụng trên máy ảo hoặc thiết bị Android thật
flutter run

# 3. Đóng gói tệp APK cài đặt
flutter build apk --release
```

---

## 📱 Cấu Hình Goong Map API Key
1. Đăng ký tài khoản miễn phí tại [Goong Console](https://account.goong.io/).
2. Tạo **MapTiles Key** và **REST API Key**.
3. Mở ứng dụng, vào tab **Cài Đặt** (biểu tượng bánh răng ở góc trên bên phải màn hình Khám Phá), dán các mã Key và nhấn **Lưu cấu hình**.
