import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/pinned_place.dart';
import '../models/trip.dart';
import '../models/vehicle_type.dart';
import '../providers/tracking_provider.dart';
import '../providers/trip_provider.dart';
import '../theme/app_theme.dart';

class TripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback onTap;
  final Function(String newTitle)? onRename;
  final VoidCallback? onDelete;

  const TripCard({
    super.key,
    required this.trip,
    required this.onTap,
    this.onRename,
    this.onDelete,
  });

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: trip.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên chuyến đi'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tên hành trình',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty && onRename != null) {
                onRename!(text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xoá'),
        content: Text('Bạn có chắc chắn muốn xoá hành trình "${trip.title}"? Dữ liệu toạ độ của chuyến đi này sẽ bị xoá khỏi bản đồ khám phá.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              if (onDelete != null) onDelete!();
            },
            child: const Text('Xoá', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('HH:mm • dd/MM/yyyy').format(trip.startTime);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(trip.vehicleType.icon, color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                          ),
                        ),
                        Builder(
                          builder: (ctx) {
                            List<PinnedPlace> pinned = const [];
                            try {
                              pinned = Provider.of<TripProvider>(ctx, listen: false).pinnedPlaces;
                            } catch (_) {}

                            PinnedPlace? findPin(String? addr) {
                              if (addr == null) return null;
                              for (final p in pinned) {
                                if (p.name == addr) return p;
                              }
                              return null;
                            }

                            final startIsHome =
                                trip.startAddress == TrackingProvider.homeAddressLabel;
                            final endIsHome =
                                trip.endAddress == TrackingProvider.homeAddressLabel;
                            final startPin = startIsHome ? null : findPin(trip.startAddress);
                            final endPin = endIsHome ? null : findPin(trip.endAddress);

                            final parts = <String>[];
                            if (startIsHome) {
                              parts.add('Xuất phát từ Nhà');
                            } else if (startPin != null) {
                              parts.add('Từ ${startPin.name}');
                            }
                            if (endIsHome) {
                              parts.add('Kết thúc tại Nhà');
                            } else if (endPin != null) {
                              parts.add('Đến ${endPin.name}');
                            }

                            if (parts.isEmpty) return const SizedBox.shrink();

                            final badgeColor = (startIsHome || endIsHome)
                                ? const Color(0xFFB45309)
                                : (startPin?.category.color ??
                                    endPin?.category.color ??
                                    const Color(0xFFB45309));
                            final badgeIcon = (startIsHome || endIsHome)
                                ? Icons.home_rounded
                                : (startPin?.category.icon ??
                                    endPin?.category.icon ??
                                    Icons.place_rounded);

                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(badgeIcon, size: 11, color: badgeColor),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        parts.join(' • '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: badgeColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(trip.vehicleType.icon, size: 11, color: Colors.indigo.shade700),
                                  const SizedBox(width: 4),
                                  Text(
                                    trip.vehicleSummaryLabel,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.indigo.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (trip.distanceKm >= 0.01)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (trip.newDistanceKm >= 0.01
                                          ? AppTheme.primary
                                          : Colors.blueGrey)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      trip.newDistanceKm >= 0.01
                                          ? Icons.explore_rounded
                                          : Icons.repeat_rounded,
                                      size: 11,
                                      color: trip.newDistanceKm >= 0.01
                                          ? AppTheme.primary
                                          : Colors.blueGrey.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      trip.newDistanceKm >= 0.01
                                          ? 'Khám phá mới +${trip.newDistanceKm.toStringAsFixed(2)} km (${trip.newDiscoveryPercent.round()}%)'
                                          : 'Trùng đường đã khám phá',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: trip.newDistanceKm >= 0.01
                                            ? AppTheme.primary
                                            : Colors.blueGrey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                      size: 20,
                    ),
                    onSelected: (val) {
                      if (val == 'rename') {
                        _showRenameDialog(context);
                      } else if (val == 'delete') {
                        _confirmDelete(context);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Đổi tên'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Xoá', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _infoChip(
                    context,
                    Icons.straighten_rounded,
                    '${trip.distanceKm.toStringAsFixed(2)} km',
                    AppTheme.primary,
                  ),
                  _infoChip(
                    context,
                    Icons.timer_outlined,
                    trip.formattedDuration,
                    AppTheme.accent,
                  ),
                  _infoChip(
                    context,
                    Icons.speed_rounded,
                    '${trip.avgSpeedKmh.toStringAsFixed(1)} km/h',
                    Colors.deepPurple,
                  ),
                  _infoChip(
                    context,
                    Icons.flag_outlined,
                    '${trip.waypoints.length} mốc',
                    Colors.teal,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(BuildContext context, IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
