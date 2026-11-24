import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/tracking_provider.dart';
import '../services/nearby_places_service.dart';
import 'place_picker_map_widget.dart';

class AddWaypointDialog extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const AddWaypointDialog({
    super.key,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<AddWaypointDialog> createState() => _AddWaypointDialogState();
}

class _AddWaypointDialogState extends State<AddWaypointDialog> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _selectedPlaceId;
  double? _selectedLat;
  double? _selectedLng;
  LatLng? _initialCenter;

  @override
  void initState() {
    super.initState();
    final pos = Provider.of<TrackingProvider>(context, listen: false).currentPosition;
    final lat = widget.initialLat ?? pos?.latitude;
    final lng = widget.initialLng ?? pos?.longitude;
    if (lat != null && lng != null) {
      _initialCenter = LatLng(lat, lng);
      _selectedLat = lat;
      _selectedLng = lng;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onPlaceSelected(NearbyPlace place) {
    setState(() {
      _selectedPlaceId = place.id;
      _selectedLat = place.latitude;
      _selectedLng = place.longitude;
      _nameController.text = place.name;
      if (place.address != null && place.address!.isNotEmpty) {
        _noteController.text = place.address!;
      } else if (place.category != null && _noteController.text.trim().isEmpty) {
        _noteController.text = place.category!;
      }
    });
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.pop(context, <String, dynamic>{
        'name': _nameController.text.trim(),
        'note': _noteController.text.trim(),
        'latitude': _selectedLat,
        'longitude': _selectedLng,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height && size.height < 540;
    final hasMap = _initialCenter != null;

    final header = const Row(
      children: [
        Icon(Icons.flag_rounded, color: Colors.orange),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Đánh dấu điểm đến',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );

    final formFields = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _nameController,
            autofocus: !hasMap,
            decoration: const InputDecoration(
              labelText: 'Tên địa điểm / Mốc khám phá',
              hintText: 'Chọn trên bản đồ hoặc nhập tên...',
              prefixIcon: Icon(Icons.place_outlined),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            onChanged: (_) {
              if (_selectedPlaceId != null) {
                setState(() => _selectedPlaceId = null);
              }
            },
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Vui lòng chọn địa điểm hoặc nhập tên';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Ghi chú / Địa chỉ (tuỳ chọn)',
              hintText: 'Cảnh đẹp, quán quen...',
              prefixIcon: Icon(Icons.note_alt_outlined),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            maxLines: isLandscape ? 1 : 2,
          ),
        ],
      ),
    );

    final actionButtons = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Lưu điểm'),
        ),
      ],
    );

    if (isLandscape && hasMap) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (size.width * 0.92).clamp(360.0, 760.0),
            maxHeight: size.height * 0.90,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: PlacePickerMapWidget(
                    center: _initialCenter!,
                    expandMap: true,
                    selectedPlaceId: _selectedPlaceId,
                    selectedPoint: _selectedLat != null && _selectedLng != null
                        ? LatLng(_selectedLat!, _selectedLng!)
                        : null,
                    onPlaceSelected: _onPlaceSelected,
                    onMapPointTapped: (pt) {
                      setState(() {
                        _selectedPlaceId = null;
                        _selectedLat = pt.latitude;
                        _selectedLng = pt.longitude;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      const SizedBox(height: 10),
                      Expanded(
                        child: SingleChildScrollView(child: formFields),
                      ),
                      const SizedBox(height: 8),
                      actionButtons,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: size.height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (hasMap) ...[
                const SizedBox(height: 12),
                PlacePickerMapWidget(
                  center: _initialCenter!,
                  mapHeight: (size.height * 0.26).clamp(165.0, 220.0),
                  selectedPlaceId: _selectedPlaceId,
                  selectedPoint: _selectedLat != null && _selectedLng != null
                      ? LatLng(_selectedLat!, _selectedLng!)
                      : null,
                  onPlaceSelected: _onPlaceSelected,
                  onMapPointTapped: (pt) {
                    setState(() {
                      _selectedPlaceId = null;
                      _selectedLat = pt.latitude;
                      _selectedLng = pt.longitude;
                    });
                  },
                ),
              ],
              const SizedBox(height: 12),
              formFields,
              const SizedBox(height: 12),
              actionButtons,
            ],
          ),
        ),
      ),
    );
  }
}
