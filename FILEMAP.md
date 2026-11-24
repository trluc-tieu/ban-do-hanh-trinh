# 🗺️ FILEMAP — Bản Đồ Hành Trình (`ban_do_hanh_trinh`)

> **Mục đích:** Bản đồ tra cứu nhanh toàn bộ file trong dự án. Khi cần sửa lỗi hoặc nâng cấp tính năng, tra **Bảng 1 (Nhảy nhanh theo tính năng)** hoặc **Bảng 2 (Danh mục chi tiết từng file)** để mở thẳng đúng file cần sửa, không cần dò quét toàn bộ thư mục.
> **Quy tắc:** Mỗi khi thêm/xoá/đổi tên file hoặc thêm chức năng lớn, cập nhật ngay file này.

---

## ⚡ 1. BẢNG TRA CỨU NHANH THEO TÍNH NĂNG (FEATURE -> TARGET FILES)

| Tính năng / Yêu cầu cần sửa | Mở ngay các file này | Class / Hàm trọng tâm |
| :--- | :--- | :--- |
| **Tab 1: Bản đồ hợp nhất (nút tròn Play/Stop, đổi xe, vẽ live & ẩn ghim khi chạy)** | `lib/screens/discovery_map_screen.dart`<br>`lib/screens/main_screen.dart`<br>`lib/providers/tracking_provider.dart` | `DiscoveryMapScreen`, `MainScreen` (5 tab), `startTracking()`, `stopTracking()`, `setCurrentVehicleType()` |
| **Theo dõi chạy ngầm & Tự tạo hành trình (chống nhiễu GPS)** | `lib/services/auto_trip_detector.dart`<br>`lib/providers/tracking_provider.dart`<br>`lib/services/location_service.dart` | `AutoTripDetector.evaluate()`, `configureBackgroundMonitoring()`, `_autoStartFromSamples()`, `getBackgroundMonitorStream()` |
| **Tự động kết thúc khi dừng chân lâu & Điểm dừng >= 2 phút** | `lib/providers/tracking_provider.dart`<br>`lib/widgets/pending_stay_dialog.dart`<br>`lib/services/nearby_places_service.dart` | `_startRecordingTimer()`, `_checkStationaryStop()`, `PendingStayDialog` |
| **Tính số km khám phá thực tế (loại trùng lặp đoạn đường)** | `lib/services/exploration_calculator.dart`<br>`lib/providers/trip_provider.dart`<br>`lib/screens/trip_detail_screen.dart` | `ExplorationIndex`, `LiveExplorationTracker`, `ExplorationCalculator.computeSummary()`, `classifyTripSegments()` |
| **Ghim vị trí "Nhà" & Bán kính nhận diện (50m)** | `lib/widgets/home_picker_dialog.dart`<br>`lib/services/place_search_service.dart`<br>`lib/providers/map_settings_provider.dart`<br>`lib/providers/tracking_provider.dart` | `HomePickerDialog`, `PlaceSearchService`, `setHome()`, `setHomeRadius()`, `isNearHome()` |
| **Tìm kiếm từ xa & Ghim địa điểm (Công ty, Quán quen, Trường học...)** | `lib/services/place_search_service.dart`<br>`lib/models/pinned_place.dart`<br>`lib/widgets/pinned_place_dialog.dart`<br>`lib/widgets/goong_map_widget.dart`<br>`lib/providers/trip_provider.dart` | `PlaceSearchService.searchPlaces()`, `PinnedPlace`, `PinnedPlaceDialog`, `findMatchingPinnedPlaceLabel()` |
| **Icon phương tiện, đổi xe giữa chuyến & xem lại theo thời điểm** | `lib/models/vehicle_type.dart`<br>`lib/models/track_point.dart`<br>`lib/models/trip.dart`<br>`lib/widgets/vehicle_picker_sheet.dart`<br>`lib/screens/trip_detail_screen.dart` | `VehicleType` (mặc định `motorbike`), `Trip.recordVehicleSwitch()`, `TrackPoint.vehicleType`, `VehiclePickerSheet` |
| **Hiển thị Bản đồ (Google Maps, OpenMap/NDAMaps Vector, OSM)** | `lib/widgets/goong_map_widget.dart`<br>`lib/widgets/vector_map_style_mixin.dart`<br>`lib/services/goong_service.dart`<br>`lib/services/openmap_service.dart`<br>`lib/widgets/smart_tile_provider.dart` | `GoongMapWidget`, `VectorMapStyleMixin`, `SmartTileProvider`, `GoongService`, `OpenMapService` |
| **Tải sẵn bản đồ ngoại tuyến (Offline Tiles)** | `lib/services/offline_map_service.dart`<br>`lib/widgets/offline_map_preload_dialog.dart` | `OfflineMapService`, `OfflineMapPreloadDialog` |
| **Tab 2: Khám Phá (Xếp hạng 63 Tỉnh/Thành Việt Nam & Nhận diện mọi tỉnh đi qua)** | `lib/screens/province_ranking_screen.dart`<br>`lib/models/province_stats.dart`<br>`lib/services/exploration_calculator.dart`<br>`lib/providers/trip_provider.dart` | `ProvinceRankingScreen`, `VietnamProvinces.provinceForCoordinate()` (toạ độ offline 63 tỉnh), `ExplorationCalculator.computeSummary()` (chia km theo từng tỉnh trên toàn lộ trình), `_rebuildProvinceAggregates()` |
| **Tab 3: Ảnh (Gom thư mục theo tên địa điểm & toạ độ gần nhau, không hiện bản đồ)** | `lib/screens/photo_discovery_screen.dart`<br>`lib/services/photo_discovery_service.dart` | `PhotoDiscoveryScreen`, `PhotoFolderCluster`, `PhotoDiscoveryService.groupPhotosIntoFolders()` |
| **Tab 4: Thống kê theo tháng & Biểu đồ cột** | `lib/screens/monthly_stats_screen.dart`<br>`lib/models/monthly_stats.dart`<br>`lib/widgets/monthly_bar_chart.dart` | `MonthlyStatsScreen`, `MonthlyStats.calculate()`, `MonthlyBarChart` |
| **Tab 5: Lịch sử chuyến đi & Chi tiết tua lộ trình** | `lib/screens/trips_history_screen.dart`<br>`lib/screens/trip_detail_screen.dart`<br>`lib/widgets/trip_card.dart` | `TripsHistoryScreen`, `TripDetailScreen`, `TripCard` |
| **Câu nói tâm sự / bình luận bạn đồng hành** | `lib/services/companion_quotes.dart` | `CompanionQuotes` |
| **Màn hình Cài đặt & Sao lưu Google Drive JSON** | `lib/screens/settings_screen.dart`<br>`lib/providers/map_settings_provider.dart`<br>`lib/services/database_service.dart` | `SettingsScreen`, `exportFullDatabaseJson()`, `importDatabaseJson()` |
| **Cơ sở dữ liệu SQLite (Schema & Migration)** | `lib/services/database_service.dart` | `DatabaseService` (DB `journey_discovery.db`, version `6`) |
| **Quyền Android & Icon ứng dụng** | `android/app/src/main/AndroidManifest.xml`<br>`android/app/src/main/res/mipmap-*/ic_launcher.png` | Permissions, `GeolocatorLocationService`, `@mipmap/ic_launcher` |
| **Kiểm tra cập nhật & tự cài APK mới (GitHub Releases, hỗ trợ repo private)** | `lib/services/app_update_service.dart`<br>`lib/widgets/app_update_dialog.dart`<br>`lib/screens/settings_screen.dart`<br>`android/app/src/main/kotlin/trluc/top/ban_do_hanh_trinh/MainActivity.kt`<br>`android/app/src/main/res/xml/apk_installer_paths.xml` | `AppUpdateService.checkForUpdate()`, `downloadReleaseApk()`, `installApk()`, `AppUpdateDialog.checkAndPrompt()`, MethodChannel `trluc.top/app_updater` |
| **Kiểm thử tự động (Unit Tests)** | `test/widget_test.dart`<br>`test/app_update_test.dart` | 26 bài kiểm thử models, services, đa tỉnh thành, cập nhật APK |

---

## 📂 2. DANH MỤC CHI TIẾT TOÀN BỘ FILE TRONG DỰ ÁN

### 2.1. Khởi chạy & Giao diện chủ đề (`lib/main.dart`, `lib/theme/`)
- `lib/main.dart` — Điểm khởi chạy `main()`, khởi tạo định dạng ngày tiếng Việt, `OfflineMapService`, `MultiProvider` (`MapSettingsProvider`, `TrackingProvider`, `TripProvider`) và `BanDoHanhTrinhApp`.
- `lib/theme/app_theme.dart` — Bảng màu chủ đạo (`AppTheme.primary`, `AppTheme.discoveryNeon`, `AppTheme.accent`), cấu hình `lightTheme` và `darkTheme`.

### 2.2. Mô hình dữ liệu (`lib/models/` — 8 files)
- `lib/models/trip.dart` — Thực thể chuyến đi (`Trip`): `totalDistance`, `newDistance` (km khám phá mới không trùng), `vehicleType` (mặc định `Xe máy`), `vehicleTypesUsed` & `recordVehicleSwitch()` (lưu chuỗi phương tiện đổi giữa chừng), `startAddress`, `endAddress`, `points`, `waypoints`.
- `lib/models/track_point.dart` — Điểm toạ độ GPS (`TrackPoint`): `latitude`, `longitude`, `altitude`, `speed` (`speedKmh`), `accuracy`, `timestamp`, `vehicleType` (phục vụ tua lại đúng icon xe tại từng thời điểm).
- `lib/models/waypoint.dart` — Điểm đánh dấu check-in thủ công hoặc từ ảnh EXIF (`Waypoint`, `photoPath`).
- `lib/models/stay_point.dart` — Điểm dừng chân tự động phát hiện (`StayPoint`: `pending` / `confirmed` / `rejected`).
- `lib/models/pinned_place.dart` — Địa điểm ghim tuỳ chỉnh trên bản đồ (`PinnedPlace` & 7 nhóm `PinnedPlaceCategory`: Công ty, Trường học, Quán quen, Quán ăn, Tham quan, Bãi xe, Yêu thích kèm icon/màu riêng).
- `lib/models/vehicle_type.dart` — 7 loại biểu tượng phương tiện (`VehicleType`), góc xoay và bảng màu `kVehicleColors`.
- `lib/models/monthly_stats.dart` — Dữ liệu thống kê tháng (`MonthlyStats`): `totalDistanceKm`, `newDistanceKm`, `distanceByDay`, `newDistanceByDay`.
- `lib/models/province_stats.dart` — Dữ liệu & tọa độ nhận diện 63 tỉnh thành Việt Nam (`VietnamProvinces.provinceForCoordinate()`, `ProvinceStats` với `distanceKm` và `traveledKm`).
- `lib/services/exploration_calculator.dart` — Lưới băm không gian `ExplorationIndex` (sai số làn đường `25m`, chia đoạn `20m`, trễ góc cua `60m`), `LiveExplorationTracker` và `ExplorationCalculator` tính chính xác km đường mới không trùng lặp và phân rã km theo từng tỉnh trên toàn lộ trình (`traveledMetersByTripProvince`, `newMetersByTripProvince`).

### 2.3. Quản lý trạng thái (`lib/providers/` — 3 files)
- `lib/providers/tracking_provider.dart` — Điều phối ghi hành trình thời gian thực (khởi động tức thì `< 30ms`), tắt GPS nền khi nghỉ để tiết kiệm pin (`refreshCurrentLocationOnce()` khi bấm định vị), đổi phương tiện giữa chuyến (`setCurrentVehicleType`), theo dõi chạy ngầm tự mở chuyến (`configureBackgroundMonitoring`), đếm `currentNewDistanceKm` trực tiếp, tự ngắt khi dừng lâu.
- `lib/providers/trip_provider.dart` — Quản lý danh sách chuyến đi, lộ trình khám phá, tính lại km khám phá duy nhất (`_recomputeExplorationMetrics`), phân rã km/chuyến theo từng tỉnh trên toàn tuyến (`_rebuildProvinceAggregates`), quản lý `pinnedPlaces`, xếp hạng tỉnh và thống kê tháng.
- `lib/providers/map_settings_provider.dart` — Lưu trữ cài đặt vào `SharedPreferences`: nguồn bản đồ, API keys, lọc khoảng cách GPS, tự động ngắt khi dừng, bật/tắt chạy ngầm (`backgroundAutoTrack`, ngưỡng tốc độ & phạm vi), xe/màu/xoay bản đồ, ghim `"Nhà"` (bán kính mặc định `50m`).

### 2.4. Màn hình chính (`lib/screens/` — 8 files)
- `lib/screens/main_screen.dart` — Khung điều hướng 5 tab dưới đáy (`Bản Đồ`, `Khám Phá`, `Ảnh`, `Thống Kê`, `Lịch Sử` — dọc `NavigationBar`, ngang `NavigationRail`) và đồng bộ cấu hình chạy ngầm/phương tiện vào `TrackingProvider`.
- `lib/screens/discovery_map_screen.dart` — Tab 1 (`Bản Đồ` hợp nhất): vừa hiển thị cung đường đã mở khoá vừa vẽ polyline trực tiếp & cộng km thời gian thực khi đang ghi; ẩn ghim check-in/ảnh khi bắt đầu chạy và hiện lại khi dừng; cụm nút tròn tối giản Play/Stop + chọn phương tiện + hộp thoại hoàn thành chuyến.
- `lib/screens/province_ranking_screen.dart` — Tab 2 (`Khám Phá`): Bảng xếp hạng mở khoá 63 Tỉnh/Thành Việt Nam kèm ghi chú thân thiện theo dữ liệu.
- `lib/screens/photo_discovery_screen.dart` — Tab 3 (`Ảnh`): Bộ sưu tập ảnh theo thư mục địa điểm (không hiển thị bản đồ), tự gom các ảnh cùng tên hoặc gần toạ độ vào chung 1 thư mục.
- `lib/screens/monthly_stats_screen.dart` — Tab 4 (`Thống Kê`): Thống kê theo tháng (`Khám phá mới`, `Tổng quãng đường`, biểu đồ ngày, danh sách chuyến trong tháng).
- `lib/screens/trips_history_screen.dart` — Tab 5 (`Lịch Sử`): Lịch sử toàn bộ hành trình, tìm kiếm, thanh tổng hợp 4 chỉ số.
- `lib/screens/trip_detail_screen.dart` — Xem chi tiết 1 chuyến đi: bản đồ phân màu đoạn **Mới** vs **Đã đi**, hiển thị chuỗi phương tiện của chuyến và tự đổi icon phương tiện theo đúng thời điểm khi kéo thanh tua lại.
- `lib/screens/settings_screen.dart` — Cài đặt đầy đủ: nguồn bản đồ, API key Google / OpenMap-NDAMaps, biểu tượng xe & la bàn, vị trí Nhà, danh sách địa điểm ghim khác, tải bản đồ offline, chạy ngầm tự động ghi, tự ngắt khi dừng, sao lưu/khôi phục Google Drive.

### 2.5. Dịch vụ nền & Thuật toán (`lib/services/` — 14 files)
- `lib/services/app_update_service.dart` — `AppUpdateService`: gọi GitHub API `releases/latest` (kèm token nếu repo private), so sánh `AppVersionInfo`, tải APK có tiến trình/huỷ (xử lý redirect S3 không gửi lại token) và gọi MethodChannel `trluc.top/app_updater` để mở trình cài đặt.
- `lib/services/place_search_service.dart` — Tìm kiếm địa điểm từ xa theo tên / địa chỉ / toạ độ (`PlaceSearchService`: OpenMap Autocomplete & Forward Geocode, Google Geocoding, OSM Nominatim tiếng Việt miễn phí, và fallback 63 tỉnh offline) kèm tự đoán loại biểu tượng (`inferCategory`).
- `lib/services/exploration_calculator.dart` — Lưới băm không gian `ExplorationIndex` (sai số làn đường `25m`, chia đoạn `20m`, trễ góc cua `60m`), `LiveExplorationTracker` và `ExplorationCalculator` tính chính xác km đường mới không trùng lặp.
- `lib/services/auto_trip_detector.dart` — Thuật toán `AutoTripDetector` kiểm tra tốc độ duy trì + phạm vi ròng + tỷ lệ hướng thẳng, chống nhiễu GPS đứng yên/đi bộ quanh chỗ và hoàn trả mẫu xuất phát (`departureSamples`).
- `lib/services/database_service.dart` — SQLite `journey_discovery.db` (v6): các bảng `trips` (lưu `vehicle_type`, `vehicle_types`), `track_points` (lưu `vehicle_type` theo từng mốc), `waypoints`, `stay_points`, `pinned_places` và xuất/nhập JSON toàn phần.
- `lib/services/location_service.dart` — Giao tiếp `Geolocator` & quyền GPS/Notification: luồng ghi hành trình, luồng chờ nhẹ, và luồng canh gác chạy ngầm (`getBackgroundMonitorStream`).
- `lib/services/compass_service.dart` — Nhận góc hướng điện thoại từ `EventChannel("trluc.top/compass")`, làm mượt góc quay 360° và tự tạm dừng theo vòng đời app.
- `lib/services/companion_quotes.dart` — Sinh câu chào và nhận xét thân thiện dựa trên số liệu thật cho các tab Khám phá, Xếp hạng tỉnh, Tháng, Ảnh, Lịch sử.
- `lib/services/goong_service.dart` — Quản lý URL tile Google Maps / OSM / ESRI / Topo và dịch ngược toạ độ (Google Geocoding -> OpenMap -> Nominatim -> Offline 63 tỉnh).
- `lib/services/openmap_service.dart` — Tích hợp Vector Style (`day-v1`, `night-v1`, `satellite-v1`), đính kèm `apikey` và Reverse Geocoding cho `openmap.vn` / `ndamaps.vn`.
- `lib/services/nearby_places_service.dart` — Tìm địa điểm thực tế quanh toạ độ dừng chân (OpenMap Autocomplete/Nearby + OSM Overpass API) để chọn tên check-in 1 chạm.
- `lib/services/offline_map_service.dart` — Tải trước và phân vùng lưu trữ các mảnh bản đồ ngoại tuyến theo từng nhà cung cấp.
- `lib/services/photo_discovery_service.dart` — Đọc thẻ EXIF GPS từ file ảnh chuyển sang độ thập phân và gom nhóm ảnh thành thư mục (`PhotoFolderCluster`, `groupPhotosIntoFolders`) theo tên địa điểm hoặc bán kính lân cận `250m`.
- `lib/services/external_map_service.dart` — Mở toạ độ ra ứng dụng Google Maps hoặc tìm ảnh theo ngày/vị trí trên Google Photos.

### 2.6. Thành phần giao diện tái sử dụng (`lib/widgets/` — 15 files)
- `lib/widgets/app_update_dialog.dart` — `AppUpdateDialog.checkAndPrompt()`: hộp thoại kiểm tra cập nhật, hỏi tải về, thanh tiến trình, tự gọi trình cài đặt; hộp nhập GitHub token khi repo private.
- `lib/widgets/goong_map_widget.dart` — Bản đồ trung tâm: vẽ lộ trình khám phá, phân màu đường mới/cũ, bám theo & xoay hướng xe, hiển thị ghim Nhà + `PinnedPlace`, nhấn giữ hoặc bấm nút để ghim địa điểm mới.
- `lib/widgets/user_location_marker.dart` — Vẽ marker người dùng/phương tiện kèm chùm tia la bàn, `HomePinMarker` và `PinnedPlaceMarker`.
- `lib/widgets/pinned_place_dialog.dart` — Hộp thoại tìm kiếm tên địa điểm từ xa (`Ghim ngay` 1 chạm hoặc bay bản đồ xem trước), chọn icon (Nhà, Công ty, Trường học, Quán quen...) & bán kính (`20m..150m`).
- `lib/widgets/home_picker_dialog.dart` — Hộp thoại tìm kiếm địa chỉ từ xa và chọn vị trí/bán kính `"Nhà"` trên bản đồ.
- `lib/widgets/vehicle_picker_sheet.dart` — Bottom sheet đổi loại phương tiện, màu sắc và công tắc xoay bản đồ.
- `lib/widgets/pending_stay_dialog.dart` — Hộp thoại xác nhận điểm dừng chân tự động kèm danh sách gợi ý địa điểm lân cận.
- `lib/widgets/add_waypoint_dialog.dart` — Hộp thoại đánh dấu điểm check-in nhanh khi đang đi kèm gợi ý địa điểm quanh đó.
- `lib/widgets/place_picker_map_widget.dart` — Bản đồ con kéo tâm ngắm để tinh chỉnh toạ độ điểm check-in / điểm dừng.
- `lib/widgets/offline_map_preload_dialog.dart` — Hộp thoại tải bản đồ offline theo bán kính hiện tại hoặc theo Tỉnh/Thành.
- `lib/widgets/vector_map_style_mixin.dart` — Mixin dựng lớp nền bản đồ Raster (`SmartTileProvider`) hoặc Vector (`VectorTileLayer` cho NDAMaps).
- `lib/widgets/smart_tile_provider.dart` — TileProvider ưu tiên đọc tile ngoại tuyến đã lưu trước khi tải mạng (kèm chuẩn `User-Agent` OSM).
- `lib/widgets/trip_card.dart` — Thẻ tóm tắt chuyến đi: gắn badge địa điểm ghim đầu/cuối (`Nhà`, `Công ty`...) và badge `+km khám phá mới (%)`.
- `lib/widgets/metric_card.dart` — Thẻ hiển thị chỉ số thống kê dùng chung.
- `lib/widgets/monthly_bar_chart.dart` — Biểu đồ cột `fl_chart` quãng đường theo từng ngày trong tháng.

### 2.7. Nền tảng Android Native & Cấu hình (`android/`, `test/`, gốc)
- `android/app/src/main/kotlin/trluc/top/ban_do_hanh_trinh/MainActivity.kt` — Kênh cảm biến la bàn phần cứng Android (`TYPE_ROTATION_VECTOR`) bù góc xoay màn hình; MethodChannel `trluc.top/app_updater` (`getAppVersion`, `installApk`, xin quyền cài từ nguồn này, `FileProvider`).
- `android/app/src/main/res/xml/apk_installer_paths.xml` — Đường dẫn `FileProvider` cho phép chia sẻ APK đã tải với trình cài đặt hệ thống.
- `android/app/src/main/AndroidManifest.xml` — Khai báo quyền GPS, `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS` và icon `@mipmap/ic_launcher`.
- `android/app/src/main/res/mipmap-*/ic_launcher.png` — Bộ ảnh icon launcher của ứng dụng theo mật độ màn hình (`mdpi` -> `xxxhdpi`).
- `android/app/build.gradle.kts` & `android/build.gradle.kts` — Cấu hình Gradle Android (`compileSdk = 36`, `minSdk = 21`, AGP `9.1.0`).
- `pubspec.yaml` — Khai báo dependencies, mô tả dự án và phiên bản ứng dụng.
- `README.md` — Tài liệu tổng quan dự án, kiến trúc đa bản đồ (Google Maps, OpenMap.vn/NDAMaps, OSM, Offline - không dùng Goong Map), 9 nhóm tính năng nổi bật và hướng dẫn cài đặt/phát triển.
- `test/widget_test.dart` — Bộ 21 unit test kiểm tra toàn diện các thuật toán, phân bổ đa tỉnh thành và model.
- `test/app_update_test.dart` — Test so sánh phiên bản và phân tích JSON release GitHub.
