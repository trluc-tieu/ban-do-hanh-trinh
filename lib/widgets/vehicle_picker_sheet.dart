import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vehicle_type.dart';
import '../providers/map_settings_provider.dart';
import '../providers/tracking_provider.dart';
import '../theme/app_theme.dart';

/// Bottom sheet allowing the user to customize the vehicle icon and color
/// displayed while recording a journey, plus map-rotation follow mode.
class VehiclePickerSheet extends StatelessWidget {
  const VehiclePickerSheet({super.key});

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const VehiclePickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<MapSettingsProvider>(context);
    final tracking = Provider.of<TrackingProvider>(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: settings.vehicleColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: Icon(settings.vehicleType.icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Chọn biểu tượng phương tiện',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        tracking.isRecording
                            ? 'Đang chạy: đoạn đường tiếp theo sẽ ghi nhận ${settings.vehicleType.label}'
                            : 'Mặc định là Xe máy • Đang chọn: ${settings.vehicleType.label}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            const Text(
              'Kiểu phương tiện',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: VehicleType.values.map((v) {
                final selected = settings.vehicleType == v;
                return ChoiceChip(
                  avatar: Icon(
                    v.icon,
                    size: 18,
                    color: selected ? Colors.white : settings.vehicleColor,
                  ),
                  label: Text(v.label),
                  selected: selected,
                  selectedColor: settings.vehicleColor,
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? Colors.white : null,
                  ),
                  onSelected: (_) {
                    settings.setVehicleType(v);
                    tracking.setCurrentVehicleType(v);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),
            const Text(
              'Màu sắc biểu tượng',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: kVehicleColors.map((color) {
                final selected = settings.vehicleColor.toARGB32() == color.toARGB32();
                return GestureDetector(
                  onTap: () => settings.setVehicleColor(color),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.white : Colors.black12,
                        width: selected ? 3 : 1,
                      ),
                      boxShadow: selected
                          ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)]
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 14),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Xoay bản đồ theo hướng di chuyển',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Tự động xoay bản đồ theo hướng bạn đang chạy khi ghi hành trình',
                style: TextStyle(fontSize: 11.5),
              ),
              value: settings.rotateMapWithHeading,
              activeThumbColor: AppTheme.primary,
              onChanged: (v) => settings.setRotateMapWithHeading(v),
            ),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                onPressed: () => Navigator.pop(context),
                child: const Text('Xong'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
