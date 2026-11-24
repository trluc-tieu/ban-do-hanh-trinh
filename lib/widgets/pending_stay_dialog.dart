import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/stay_point.dart';
import '../providers/tracking_provider.dart';
import '../services/external_map_service.dart';
import '../services/nearby_places_service.dart';
import '../theme/app_theme.dart';
import 'place_picker_map_widget.dart';

class PendingStayDialog extends StatefulWidget {
  final StayPoint stayPoint;

  const PendingStayDialog({super.key, required this.stayPoint});

  static Future<void> show(BuildContext context, StayPoint stayPoint) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PendingStayDialog(stayPoint: stayPoint),
    );
  }

  @override
  State<PendingStayDialog> createState() => _PendingStayDialogState();
}

enum _StayChoice { confirm, adjust, reject }

class _PendingStayDialogState extends State<PendingStayDialog> {
  _StayChoice _selectedChoice = _StayChoice.confirm;
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;
  late final TextEditingController _adjustNameController;
  late final TextEditingController _adjustNoteController;

  String? _selectedPlaceId;
  late double _selectedLat;
  late double _selectedLng;

  @override
  void initState() {
    super.initState();
    _selectedLat = widget.stayPoint.latitude;
    _selectedLng = widget.stayPoint.longitude;

    final defaultName = widget.stayPoint.address != null && widget.stayPoint.address!.isNotEmpty
        ? widget.stayPoint.address!.split(',').first.trim()
        : 'Điểm dừng ${DateFormat('HH:mm').format(widget.stayPoint.arrivalTime)}';

    _nameController = TextEditingController(text: defaultName);
    _noteController = TextEditingController(text: widget.stayPoint.address ?? '');
    _adjustNameController = TextEditingController();
    _adjustNoteController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _adjustNameController.dispose();
    _adjustNoteController.dispose();
    super.dispose();
  }

  void _onPlaceSelected(NearbyPlace place) {
    setState(() {
      _selectedPlaceId = place.id;
      _selectedLat = place.latitude;
      _selectedLng = place.longitude;
      if (_selectedChoice == _StayChoice.reject) {
        _selectedChoice = _StayChoice.confirm;
      }
      final noteVal = place.address?.isNotEmpty == true
          ? place.address!
          : (place.category ?? '');
      if (_selectedChoice == _StayChoice.adjust) {
        _adjustNameController.text = place.name;
        if (noteVal.isNotEmpty) _adjustNoteController.text = noteVal;
      } else {
        _nameController.text = place.name;
        if (noteVal.isNotEmpty) _noteController.text = noteVal;
      }
    });
  }

  void _onConfirm(BuildContext context) async {
    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    final name = _nameController.text.trim().isEmpty
        ? 'Điểm dừng chân'
        : _nameController.text.trim();
    await tracking.confirmStayPoint(
      widget.stayPoint,
      name,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      latitude: _selectedLat,
      longitude: _selectedLng,
    );
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xác nhận điểm ghé thăm: "$name"'),
          backgroundColor: AppTheme.primary,
        ),
      );
    }
  }

  void _onAdjust(BuildContext context) async {
    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    final name = _adjustNameController.text.trim().isEmpty
        ? 'Địa điểm gần đó'
        : _adjustNameController.text.trim();
    await tracking.adjustStayPoint(
      widget.stayPoint,
      _selectedLat,
      _selectedLng,
      name,
      note: _adjustNoteController.text.trim().isEmpty ? null : _adjustNoteController.text.trim(),
    );
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã điều chỉnh và lưu điểm đến: "$name"'),
          backgroundColor: AppTheme.accent,
        ),
      );
    }
  }

  void _onReject(BuildContext context) async {
    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    await tracking.rejectStayPoint(widget.stayPoint);
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã bỏ qua điểm dừng này.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stay = widget.stayPoint;
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height && size.height < 540;
    final arrivalStr = DateFormat('HH:mm').format(stay.arrivalTime);
    final departureStr = DateFormat('HH:mm').format(stay.departureTime);
    final durationMin = stay.durationMinutes <= 0 ? 1 : stay.durationMinutes;

    final mapSection = PlacePickerMapWidget(
      center: LatLng(stay.latitude, stay.longitude),
      mapHeight: isLandscape ? 200 : (size.height * 0.24).clamp(155.0, 205.0),
      expandMap: isLandscape,
      selectedPlaceId: _selectedPlaceId,
      selectedPoint: LatLng(_selectedLat, _selectedLng),
      onPlaceSelected: _onPlaceSelected,
      onMapPointTapped: (pt) {
        setState(() {
          _selectedPlaceId = null;
          _selectedLat = pt.latitude;
          _selectedLng = pt.longitude;
        });
      },
    );

    final detailsAndForm = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.timer_outlined, color: Colors.orange, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Phát hiện điểm dừng chân',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Dừng $durationMin phút ($arrivalStr - $departureStr)',
                    style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 18, color: Colors.blue),
              tooltip: 'Mở trên Google Maps',
              onPressed: () {
                ExternalMapService().openGoogleMaps(
                  _selectedLat,
                  _selectedLng,
                  label: stay.address ?? 'Điểm dừng',
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Current / selected coordinate info bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on, size: 15, color: Colors.redAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  stay.address ??
                      'Toạ độ: ${_selectedLat.toStringAsFixed(4)}, ${_selectedLng.toStringAsFixed(4)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),

        if (!isLandscape) ...[
          const SizedBox(height: 10),
          mapSection,
        ],

        const SizedBox(height: 10),
        const Text(
          'Chọn tên địa điểm trên bản đồ hoặc xác nhận:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),

        // Choice 1: Confirm visited
        RadioListTile<_StayChoice>(
          value: _StayChoice.confirm,
          groupValue: _selectedChoice,
          activeColor: AppTheme.primary,
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Có, tôi đã ghé nơi này', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          subtitle: const Text('Lưu điểm mốc vừa chọn vào hành trình', style: TextStyle(fontSize: 11)),
          onChanged: (val) => setState(() => _selectedChoice = val!),
        ),

        if (_selectedChoice == _StayChoice.confirm) ...[
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 6),
            child: Column(
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên địa điểm / Quán xá / Điểm đến',
                    hintText: 'Chạm trên bản đồ hoặc tự nhập tên...',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú (tuỳ chọn)',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Choice 2: Visited nearby (adjust)
        RadioListTile<_StayChoice>(
          value: _StayChoice.adjust,
          groupValue: _selectedChoice,
          activeColor: AppTheme.accent,
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Tôi ghé địa điểm gần đó', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          subtitle: const Text('Chọn lại địa điểm trên bản đồ hoặc chỉnh tên', style: TextStyle(fontSize: 11)),
          onChanged: (val) => setState(() => _selectedChoice = val!),
        ),

        if (_selectedChoice == _StayChoice.adjust) ...[
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 6),
            child: Column(
              children: [
                TextField(
                  controller: _adjustNameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên địa điểm chính xác',
                    hintText: 'Chạm địa điểm trên bản đồ hoặc nhập tên...',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _adjustNoteController,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú điều chỉnh',
                    hintText: 'Ví dụ: Ghé quán bên đường cách 50m',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Choice 3: Reject / didn't visit
        RadioListTile<_StayChoice>(
          value: _StayChoice.reject,
          groupValue: _selectedChoice,
          activeColor: Colors.redAccent,
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Không ghé nơi này', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          subtitle: const Text('Chỉ dừng đèn đỏ, tắc đường hoặc đi ngang qua', style: TextStyle(fontSize: 11)),
          onChanged: (val) => setState(() => _selectedChoice = val!),
        ),
      ],
    );

    final bottomButtons = Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Để sau'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedChoice == _StayChoice.reject
                  ? Colors.redAccent
                  : (_selectedChoice == _StayChoice.adjust ? AppTheme.accent : AppTheme.primary),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
            onPressed: () {
              if (_selectedChoice == _StayChoice.confirm) {
                _onConfirm(context);
              } else if (_selectedChoice == _StayChoice.adjust) {
                _onAdjust(context);
              } else {
                _onReject(context);
              }
            },
            child: Text(
              _selectedChoice == _StayChoice.confirm
                  ? 'Xác nhận ghé'
                  : (_selectedChoice == _StayChoice.adjust ? 'Lưu đã điều chỉnh' : 'Bỏ qua điểm này'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );

    if (isLandscape) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (size.width * 0.94).clamp(400.0, 820.0),
            maxHeight: size.height * 0.92,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: mapSection),
                const SizedBox(width: 14),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(child: detailsAndForm),
                      ),
                      const SizedBox(height: 8),
                      bottomButtons,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: size.height * 0.90,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: detailsAndForm,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: bottomButtons,
            ),
          ],
        ),
      ),
    );
  }
}
