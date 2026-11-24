import 'dart:math';
import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ban_do_hanh_trinh/models/monthly_stats.dart';
import 'package:ban_do_hanh_trinh/models/pinned_place.dart';
import 'package:ban_do_hanh_trinh/models/province_stats.dart';
import 'package:ban_do_hanh_trinh/models/stay_point.dart';
import 'package:ban_do_hanh_trinh/models/track_point.dart';
import 'package:ban_do_hanh_trinh/models/trip.dart';
import 'package:ban_do_hanh_trinh/models/vehicle_type.dart';
import 'package:ban_do_hanh_trinh/models/waypoint.dart';
import 'package:ban_do_hanh_trinh/providers/tracking_provider.dart';
import 'package:ban_do_hanh_trinh/services/auto_trip_detector.dart';
import 'package:ban_do_hanh_trinh/services/companion_quotes.dart';
import 'package:ban_do_hanh_trinh/services/compass_service.dart';
import 'package:ban_do_hanh_trinh/services/exploration_calculator.dart';
import 'package:ban_do_hanh_trinh/services/goong_service.dart';
import 'package:ban_do_hanh_trinh/services/location_service.dart';
import 'package:ban_do_hanh_trinh/services/nearby_places_service.dart';
import 'package:ban_do_hanh_trinh/services/offline_map_service.dart';
import 'package:ban_do_hanh_trinh/services/openmap_service.dart';
import 'package:ban_do_hanh_trinh/services/photo_discovery_service.dart';
import 'package:ban_do_hanh_trinh/services/place_search_service.dart';

void main() {
  group('Trip & TrackPoint Models Test', () {
    test('TrackPoint converts speed to km/h correctly', () {
      final point = TrackPoint(
        tripId: 'trip-1',
        latitude: 21.0285,
        longitude: 105.8542,
        speed: 10.0, // 10 m/s = 36 km/h
        timestamp: DateTime(2026, 11, 10, 8, 0),
      );

      expect(point.speedKmh, closeTo(36.0, 0.01));
    });

    test('Trip formatted duration displays hh:mm:ss properly', () {
      final trip = Trip(
        id: 'trip-test',
        title: 'Chuyến đi thử nghiệm',
        startTime: DateTime(2026, 11, 10, 8, 0),
        totalDistance: 12500.0, // 12.5 km
        durationSeconds: 3725, // 1h 2m 5s
        avgSpeed: 5.0, // 18 km/h
      );

      expect(trip.distanceKm, 12.5);
      expect(trip.formattedDuration, '01:02:05');
      expect(trip.avgSpeedKmh, closeTo(18.0, 0.01));
    });

    test('Trip serialization and deserialization works seamlessly', () {
      final now = DateTime(2026, 11, 10, 9, 30);
      final trip = Trip(
        id: 'uuid-123',
        title: 'Hành trình Hồ Tây',
        startTime: now,
        totalDistance: 15400.0,
        durationSeconds: 2400,
        maxSpeed: 12.0,
        avgSpeed: 6.4,
        pointCount: 150,
        startAddress: 'Hà Nội',
        endAddress: 'Hà Nội',
        isCompleted: true,
      );

      final map = trip.toMap();
      final fromMapTrip = Trip.fromMap(map);

      expect(fromMapTrip.id, trip.id);
      expect(fromMapTrip.title, trip.title);
      expect(fromMapTrip.distanceKm, trip.distanceKm);
      expect(fromMapTrip.isCompleted, true);
    });

    test('MonthlyStats calculates monthly totals and days accurately', () {
      final t1 = Trip(
        id: '1',
        title: 'Trip 1',
        startTime: DateTime(2026, 11, 2, 9, 0),
        totalDistance: 10000.0, // 10 km
        durationSeconds: 1800, // 30 min
        avgSpeed: 5.555, // ~20 km/h
      );

      final t2 = Trip(
        id: '2',
        title: 'Trip 2',
        startTime: DateTime(2026, 11, 5, 14, 0),
        totalDistance: 15000.0, // 15 km
        durationSeconds: 2700, // 45 min
        avgSpeed: 5.555,
      );

      final stats = MonthlyStats.calculate(2026, 11, [t1, t2], 3);

      expect(stats.tripCount, 2);
      expect(stats.totalDistanceKm, 25.0);
      expect(stats.totalDurationSeconds, 4500);
      expect(stats.waypointCount, 3);
      expect(stats.distanceByDay[2], 10.0);
      expect(stats.distanceByDay[5], 15.0);
      expect(stats.distanceByDay[1], 0.0);
    });

    test('Waypoint model works as expected', () {
      final wp = Waypoint(
        id: 'wp-1',
        tripId: 'trip-1',
        name: 'Chùa Trấn Quốc',
        note: 'Điểm dừng chân',
        latitude: 21.048,
        longitude: 105.836,
        timestamp: DateTime(2026, 11, 10, 10, 0),
      );

      final map = wp.toMap();
      final fromMapWp = Waypoint.fromMap(map);

      expect(fromMapWp.id, 'wp-1');
      expect(fromMapWp.name, 'Chùa Trấn Quốc');
      expect(fromMapWp.note, 'Điểm dừng chân');
    });

    test('StayPoint model calculates duration and serializes correctly', () {
      final arrival = DateTime(2026, 11, 10, 14, 0);
      final departure = DateTime(2026, 11, 10, 14, 25); // 25 minutes
      final stay = StayPoint(
        id: 'stay-1',
        tripId: 'trip-1',
        latitude: 21.0285,
        longitude: 105.8542,
        arrivalTime: arrival,
        departureTime: departure,
        address: 'Hồ Hoàn Kiếm, Hà Nội',
        status: 'pending',
      );

      expect(stay.durationMinutes, 25);
      expect(stay.status, 'pending');

      final map = stay.toMap();
      final fromMapStay = StayPoint.fromMap(map);
      expect(fromMapStay.id, 'stay-1');
      expect(fromMapStay.durationMinutes, 25);
      expect(fromMapStay.address, 'Hồ Hoàn Kiếm, Hà Nội');
    });

    test('VietnamProvinces matches provinces correctly', () {
      expect(VietnamProvinces.allProvinces.length, 63);

      final hanoi = VietnamProvinces.matchProvince(21.0285, 105.8542, 'Hà Nội, Việt Nam');
      expect(hanoi, 'Hà Nội');

      final danang = VietnamProvinces.matchProvince(16.06, 108.24, 'Đà Nẵng');
      expect(danang, 'Đà Nẵng');

      final saigon = VietnamProvinces.matchProvince(10.77, 106.69, 'Quận 1, TP. Hồ Chí Minh');
      expect(saigon, 'TP. Hồ Chí Minh');
    });

    test('ProvinceStats calculates tier names properly', () {
      final elite = ProvinceStats(provinceName: 'Hà Nội', distanceKm: 120.5, tripCount: 5, waypointCount: 12);
      expect(elite.tierName, 'Khám Phá Toàn Diện');

      final deep = ProvinceStats(provinceName: 'Đà Nẵng', distanceKm: 55.0, tripCount: 3, waypointCount: 5);
      expect(deep.tierName, 'Khám Phá Sâu');

      final visited = ProvinceStats(provinceName: 'Quảng Ninh', distanceKm: 25.0, tripCount: 1, waypointCount: 2);
      expect(visited.tierName, 'Đã Ghé Thăm');

      final starter = ProvinceStats(provinceName: 'Ninh Bình', distanceKm: 5.0, tripCount: 1, waypointCount: 1);
      expect(starter.tierName, 'Mới Đặt Chân');
    });
    test('Waypoint with photoPath serializes and identifies photos correctly', () {
      final photoWp = Waypoint(
        id: 'photo-1',
        tripId: 'photo-discovery',
        name: 'Check-in Cầu Rồng',
        note: 'Đà Nẵng, Việt Nam',
        latitude: 16.061,
        longitude: 108.227,
        timestamp: DateTime(2026, 11, 10, 16, 45),
        photoPath: '/storage/emulated/0/DCIM/Camera/IMG_20261110.jpg',
      );

      expect(photoWp.hasPhoto, true);
      expect(photoWp.photoPath, '/storage/emulated/0/DCIM/Camera/IMG_20261110.jpg');

      final map = photoWp.toMap();
      final deserialized = Waypoint.fromMap(map);
      expect(deserialized.hasPhoto, true);
      expect(deserialized.name, 'Check-in Cầu Rồng');
      expect(deserialized.photoPath, '/storage/emulated/0/DCIM/Camera/IMG_20261110.jpg');

      final textWp = Waypoint(
        id: 'text-1',
        tripId: 'trip-1',
        name: 'Quán nước',
        latitude: 16.0,
        longitude: 108.0,
        timestamp: DateTime.now(),
      );
      expect(textWp.hasPhoto, false);
      expect(textWp.photoPath, isNull);
    });

    test('PhotoDiscoveryService correctly parses EXIF IfdRatios to decimal degrees', () {
      // Hanoi coordinates: 21° 1' 42.5" N
      final latRatios = IfdRatios([
        Ratio(21, 1),
        Ratio(1, 1),
        Ratio(425, 10),
      ]);

      final lat = PhotoDiscoveryService.ratioListToDecimal(latRatios, 'N');
      expect(lat, isNotNull);
      expect(lat!, closeTo(21.028472, 0.0001));

      // Longitude: 105° 51' 15.84" E
      final lngRatios = IfdRatios([
        Ratio(105, 1),
        Ratio(51, 1),
        Ratio(1584, 100),
      ]);

      final lng = PhotoDiscoveryService.ratioListToDecimal(lngRatios, 'E');
      expect(lng, isNotNull);
      expect(lng!, closeTo(105.8544, 0.0001));

      // Test South / West coordinates
      final southLat = PhotoDiscoveryService.ratioListToDecimal(latRatios, 'S');
      expect(southLat!, closeTo(-21.028472, 0.0001));

      // Test parsing from printable string
      final fromPrintable = PhotoDiscoveryService.ratioListToDecimal(null, 'N', '[21, 1, 42.5]');
      expect(fromPrintable, isNotNull);
      expect(fromPrintable!, closeTo(21.028472, 0.0001));

      // Test EXIF date parsing
      final date = PhotoDiscoveryService.parseExifDate('2026:11:10 16:45:30');
      expect(date, DateTime(2026, 11, 10, 16, 45, 30));
    });

    test('OpenMapService supports openmap.vn and ndamaps.vn vector styles and apikey injection', () {
      final service = OpenMapService();
      service.setApiKey('my_openmap_key');
      service.setDomain('openmap.vn');
      service.setCustomTileUrl(null);

      expect(service.apiKey, 'my_openmap_key');
      expect(service.domain, 'openmap.vn');
      expect(service.getVectorStyleUrl(), 'https://maptiles.openmap.vn/styles/day-v1/style.json?apikey=my_openmap_key');
      expect(service.getVectorStyleUrl(styleId: 'night-v1'),
          'https://maptiles.openmap.vn/styles/night-v1/style.json?apikey=my_openmap_key');

      service.setDomain('ndamaps.vn');
      expect(service.domain, 'ndamaps.vn');
      expect(service.getVectorStyleUrl(styleId: 'satellite-v1'),
          'https://maptiles.ndamaps.vn/styles/satellite-v1/style.json?apikey=my_openmap_key');

      // Ensure {z}/{x}/{y} placeholders stay unescaped while apikey is appended
      expect(
        OpenMapService.ensureApiKeyInUrl('https://maptiles.ndamaps.vn/data/base/{z}/{x}/{y}.pbf?version=4', 'abc123'),
        'https://maptiles.ndamaps.vn/data/base/{z}/{x}/{y}.pbf?version=4&apikey=abc123',
      );
      expect(
        OpenMapService.ensureApiKeyInUrl('https://maptiles.openmap.vn/data/base/{z}/{x}/{y}.pbf?apikey=existing', 'abc123'),
        'https://maptiles.openmap.vn/data/base/{z}/{x}/{y}.pbf?apikey=existing',
      );
    });

    test('GoongService identifies vector vs raster styles accurately', () {
      final service = GoongService();
      expect(GoongService.isVectorStyle(MapStyleType.openmapVn), true);
      expect(GoongService.isVectorStyle(MapStyleType.openmapVnNight), true);
      expect(GoongService.isVectorStyle(MapStyleType.openmapVnSatellite), true);
      expect(GoongService.isVectorStyle(MapStyleType.googleStreets), false);
      expect(GoongService.isVectorStyle(MapStyleType.openStreetMap), false);

      expect(GoongService.vectorStyleId(MapStyleType.openmapVn), 'day-v1');
      expect(GoongService.vectorStyleId(MapStyleType.openmapVnNight), 'night-v1');
      expect(GoongService.vectorStyleId(MapStyleType.openmapVnSatellite), 'satellite-v1');

      expect(service.getTileUrl(MapStyleType.googleStreets), contains('mt1.google.com/vt/lyrs=m&hl=vi&gl=VN'));
      expect(service.getTileUrl(MapStyleType.googleHybrid), contains('mt1.google.com/vt/lyrs=y&hl=vi&gl=VN'));
      expect(service.getTileUrl(MapStyleType.googleSatellite), contains('mt1.google.com/vt/lyrs=s&hl=vi&gl=VN'));
      expect(service.getTileUrl(MapStyleType.googleTerrain), contains('mt1.google.com/vt/lyrs=p&hl=vi&gl=VN'));
      expect(service.getTileUrl(MapStyleType.openStreetMap), 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
      expect(service.getTileUrl(MapStyleType.osmHot), 'https://tile.openstreetmap.fr/hot/{z}/{x}/{y}.png');
      expect(service.getTileUrl(MapStyleType.esriSatellite), contains('server.arcgisonline.com'));
      expect(service.getTileUrl(MapStyleType.openmapVn), contains('style.json'));
    });

    test('OfflineMapService converts LatLng to slippy map tiles and partitions source IDs accurately', () {
      // Hanoi coordinates (21.0285, 105.854) at zoom 12
      final tile = OfflineMapService.latLngToTile(21.0285, 105.8544, 12);
      expect(tile.z, 12);
      expect(tile.x, greaterThan(0));
      expect(tile.y, greaterThan(0));

      // Verify source partitioning
      expect(OfflineMapService.getSourceId('https://mt1.google.com/vt/lyrs=m&hl=vi'), 'google_streets');
      expect(OfflineMapService.getSourceId('https://mt1.google.com/vt/lyrs=y&hl=vi'), 'google_hybrid');
      expect(OfflineMapService.getSourceId('https://tile.openstreetmap.org/{z}/{x}/{y}.png'), 'osm');

      // Test radius tile calculation
      final tiles = OfflineMapService().calculateTilesForRadius(
        centerLat: 21.0285,
        centerLng: 105.8544,
        radiusKm: 3.0,
        minZoom: 12,
        maxZoom: 13,
      );
      expect(tiles.isNotEmpty, true);
      expect(tiles.every((t) => t.z >= 12 && t.z <= 13), true);

      // Verify TileCoord equality
      const c1 = TileCoord(12, 100, 200);
      const c2 = TileCoord(12, 100, 200);
      expect(c1, c2);
      expect(c1.hashCode, c2.hashCode);
    });

    test('NearbyPlacesService parses OpenMap GeoJSON, Overpass POIs, and ranks closest-first', () {
      const originLat = 21.0285;
      const originLng = 105.8542;

      final distSame = NearbyPlacesService.distanceBetweenMeters(
        originLat,
        originLng,
        originLat,
        originLng,
      );
      expect(distSame, closeTo(0.0, 0.01));

      final openMapSample = {
        'features': [
          {
            'geometry': {
              'coordinates': [105.8545, 21.0289],
            },
            'properties': {
              'id': 'om-1',
              'name': 'Highlands Coffee',
              'short_address': '5 Đinh Tiên Hoàng, Hoàn Kiếm',
              'category': ['cafe'],
              'distance': 54.0,
            },
          },
          {
            'geometry': {
              'coordinates': [105.8560, 21.0295],
            },
            'properties': {
              'id': 'om-2',
              'name': 'Nhà hát Lớn Hà Nội',
              'label': '1 Tràng Tiền',
              'category': ['attraction'],
            },
          },
        ],
      };

      final omPlaces = NearbyPlacesService.parseOpenMapGeoJson(
        openMapSample,
        originLat,
        originLng,
      );
      expect(omPlaces.length, 2);
      expect(omPlaces[0].name, 'Highlands Coffee');
      expect(omPlaces[0].category, 'Quán cà phê');
      expect(omPlaces[0].formattedDistance, '54m');
      expect(omPlaces[1].distanceMeters, greaterThan(100));

      final overpassSample = {
        'elements': [
          {
            'type': 'node',
            'id': 101,
            'lat': 21.0288,
            'lon': 105.8544,
            'tags': {
              'name': 'Highlands Coffee',
              'amenity': 'cafe',
            },
          },
          {
            'type': 'way',
            'id': 202,
            'center': {'lat': 21.0286, 'lon': 105.8543},
            'tags': {
              'name': 'Đền Ngọc Sơn',
              'tourism': 'attraction',
              'addr:street': 'Đinh Tiên Hoàng',
            },
          },
        ],
      };

      final osmPlaces = NearbyPlacesService.parseOverpassJson(
        overpassSample,
        originLat,
        originLng,
      );
      expect(osmPlaces.length, 2);
      expect(osmPlaces[1].name, 'Đền Ngọc Sơn');
      expect(osmPlaces[1].address, 'Đinh Tiên Hoàng');

      final merged = NearbyPlacesService.mergeAndRankPlaces([
        ...omPlaces,
        ...osmPlaces,
      ]);

      // Deduplicated 'Highlands Coffee' while keeping Đền Ngọc Sơn & Nhà hát Lớn
      expect(merged.length, 3);
      // Closest place first (Đền Ngọc Sơn is ~15m vs Highlands ~54m vs Nhà hát Lớn >200m)
      expect(merged.first.name, 'Đền Ngọc Sơn');
      expect(merged[1].name, 'Highlands Coffee');
      expect(merged[1].address, '5 Đinh Tiên Hoàng, Hoàn Kiếm');
      expect(merged.last.name, 'Nhà hát Lớn Hà Nội');
    });

    test('VehicleType, CompassService smoothing, Home detection, and CompanionQuotes work accurately', () {
      // VehicleType mapping & orientation flags
      expect(VehicleTypeInfo.fromIndex(null), VehicleType.motorbike);
      expect(VehicleTypeInfo.fromIndex(99), VehicleType.motorbike);
      expect(VehicleTypeInfo.fromIndex(VehicleType.car.index), VehicleType.car);
      expect(VehicleType.motorbike.isSideView, true);
      expect(VehicleType.car.isSideView, false);
      expect(VehicleType.arrow.rotatesWithHeading, true);

      // Compass wrap-around smoothing across 360 -> 0 degrees
      final smoothed = CompassService.smoothHeading(355.0, 5.0, factor: 0.5);
      expect(smoothed, closeTo(0.0, 0.01));

      // Home radius check (~111m for 0.001 deg lat)
      expect(
        TrackingProvider.isNearHome(
          21.0295,
          105.8542,
          homeLat: 21.0285,
          homeLng: 105.8542,
          radiusMeters: 200,
        ),
        true,
      );
      expect(
        TrackingProvider.isNearHome(
          21.0320,
          105.8542,
          homeLat: 21.0285,
          homeLng: 105.8542,
          radiusMeters: 200,
        ),
        false,
      );

      // Companion quotes
      expect(
        CompanionQuotes.launchGreeting,
        'Chúng ta bắt đầu khám phá những cung đường mới chứ?',
      );
      final trips = [
        Trip(
          id: 't1',
          title: 'Trip 1',
          startTime: DateTime(2026, 11, 12, 8, 0),
          startAddress: TrackingProvider.homeAddressLabel,
          endAddress: 'Hà Nội',
        ),
        Trip(
          id: 't2',
          title: 'Trip 2',
          startTime: DateTime(2026, 11, 12, 18, 0),
          startAddress: 'Cầu Giấy',
          endAddress: TrackingProvider.homeAddressLabel,
        ),
      ];
      expect(CompanionQuotes.countHomeTrips(trips), 2);
      expect(
        CompanionQuotes.pickHistoryQuote(trips: trips, random: Random(0)),
        anyOf(contains('Nhà'), contains('chuyến')),
      );
      expect(
        CompanionQuotes.pickPhotoQuote(totalPhotos: 5, provinceCount: 2, random: Random(0)),
        isNotEmpty,
      );
    });

    test('ExplorationCalculator deduplicates overlapping roads accurately across trips and round trips', () {
      // Build a line of points spaced ~100m apart (< 500m jump threshold)
      List<TrackPoint> buildLine(
        String tripId,
        double startLat,
        double startLng,
        double endLat,
        double endLng,
        int steps,
      ) {
        final list = <TrackPoint>[];
        for (int i = 0; i <= steps; i++) {
          final t = i / steps;
          list.add(TrackPoint(
            tripId: tripId,
            latitude: startLat + (endLat - startLat) * t,
            longitude: startLng + (endLng - startLng) * t,
            timestamp: DateTime(2026, 11, 13, 8, 0).add(Duration(seconds: i * 10)),
          ));
        }
        return list;
      }

      double totalPolylineMeters(List<TrackPoint> pts) {
        double sum = 0;
        for (int i = 1; i < pts.length; i++) {
          sum += LocationService.calculateDistance(
            pts[i - 1].latitude,
            pts[i - 1].longitude,
            pts[i].latitude,
            pts[i].longitude,
          );
        }
        return sum;
      }

      // Trip 1: 20 km straight North from (21.0000, 105.8000) to (21.1800, 105.8000)
      final pts1 = buildLine('trip1', 21.0000, 105.8000, 21.1800, 105.8000, 200);
      final dist1 = totalPolylineMeters(pts1);
      expect(dist1 / 1000.0, closeTo(20.0, 0.2));

      // Trip 2: 10 km overlapping Trip 1 (with 8m lateral GPS offset, e.g. opposite lane)
      // from (21.0000, 105.80008) -> (21.0900, 105.80008), then 10 km East -> (21.0900, 105.8963)
      final pts2LegOverlap = buildLine('trip2', 21.0000, 105.80008, 21.0900, 105.80008, 100);
      final pts2LegNew = buildLine('trip2', 21.0900, 105.80008, 21.0900, 105.8963, 100).skip(1).toList();
      final pts2 = [...pts2LegOverlap, ...pts2LegNew];
      final dist2 = totalPolylineMeters(pts2);
      expect(dist2 / 1000.0, closeTo(20.0, 0.2));

      final trip1 = Trip(
        id: 'trip1',
        title: 'Chuyến 1',
        startTime: DateTime(2026, 11, 13, 8, 0),
        totalDistance: dist1,
      );
      final trip2 = Trip(
        id: 'trip2',
        title: 'Chuyến 2',
        startTime: DateTime(2026, 11, 13, 10, 0),
        totalDistance: dist2,
      );

      final summary = ExplorationCalculator.computeSummary(
        [trip2, trip1], // intentionally unsorted to test chronological sorting
        {'trip1': pts1, 'trip2': pts2},
      );

      // Trip 1 = 20km new; Trip 2 = 10km new (10km overlap); Total unique = 30km; Total traveled = 40km!
      expect(summary.newMetersByTripId['trip1']! / 1000.0, closeTo(20.0, 0.2));
      expect(summary.newMetersByTripId['trip2']! / 1000.0, closeTo(10.0, 0.2));
      expect(summary.totalUniqueExploredMeters / 1000.0, closeTo(30.0, 0.3));
      expect(summary.totalTraveledMeters / 1000.0, closeTo(40.0, 0.3));

      // Verify TripSegmentBreakdown classifies repeated vs new polylines cleanly
      final priorIndex = ExplorationIndex()..addTripPoints(pts1);
      final breakdown = priorIndex.classifyTripSegments(pts2);
      expect(breakdown.repeatedMeters / 1000.0, closeTo(10.0, 0.2));
      expect(breakdown.newMeters / 1000.0, closeTo(10.0, 0.2));
      expect(breakdown.repeatedPolylines, isNotEmpty);
      expect(breakdown.newPolylines, isNotEmpty);

      // Verify LiveExplorationTracker incremental updates match batch result
      final live = LiveExplorationTracker()..seedFromRoutes({'trip1': pts1});
      for (final p in pts2) {
        live.addPoint(p.latitude, p.longitude);
      }
      expect(live.newMeters / 1000.0, closeTo(10.0, 0.2));

      // Verify single-trip round-trip (10km out + 10km back = 20km traveled, ~10km unique explored)
      final ptsOut = buildLine('round', 21.0000, 105.9000, 21.0900, 105.9000, 100);
      final ptsBack = buildLine('round', 21.0900, 105.9000, 21.0000, 105.9000, 100).skip(1).toList();
      final roundPts = [...ptsOut, ...ptsBack];
      final roundIndex = ExplorationIndex();
      final roundNewKm = roundIndex.evaluateAndAddTrip(roundPts) / 1000.0;
      expect(roundNewKm, closeTo(10.0, 0.25));
    });

    test('AutoTripDetector, PinnedPlace, and tighter 50m Home radius work reliably', () {
      // 1. Tighter default 50m Home detection: 33m -> true, 85m -> false
      expect(
        TrackingProvider.isNearHome(
          21.0288, // ~33m north of 21.0285
          105.8542,
          homeLat: 21.0285,
          homeLng: 105.8542,
        ),
        true,
      );
      expect(
        TrackingProvider.isNearHome(
          21.0293, // ~89m north of 21.0285
          105.8542,
          homeLat: 21.0285,
          homeLng: 105.8542,
        ),
        false,
      );

      // 2. PinnedPlace serialization & categories
      final cafe = PinnedPlace(
        id: 'pin-1',
        name: 'Quán Café Quen',
        category: PinnedPlaceCategory.cafe,
        latitude: 21.031,
        longitude: 105.852,
        radiusMeters: 50,
        note: 'Hay ngồi làm việc',
        createdAt: DateTime(2026, 11, 24, 9, 0),
      );
      final restored = PinnedPlace.fromMap(cafe.toMap());
      expect(restored.name, 'Quán Café Quen');
      expect(restored.category, PinnedPlaceCategory.cafe);
      expect(restored.radiusMeters, 50);
      expect(restored.note, 'Hay ngồi làm việc');
      expect(PinnedPlaceCategory.values.length, 7);

      // 3. AutoTripDetector rejects indoor noisy GPS drift & slow walking
      final detector = AutoTripDetector(minSpeedKmh: 12.0, minRangeMeters: 150);
      final t0 = DateTime(2026, 11, 24, 8, 0, 0);

      // Noisy indoor drift (accuracy = 80m > 45m) -> ignored
      expect(
        detector.evaluate(AutoTripSample(
          latitude: 21.0000,
          longitude: 105.8000,
          speedMps: 6.0,
          accuracyMeters: 80.0,
          timestamp: t0,
        )).triggered,
        false,
      );

      // Anchor at home
      expect(
        detector.evaluate(AutoTripSample(
          latitude: 21.0000,
          longitude: 105.8000,
          speedMps: 0.2,
          accuracyMeters: 10.0,
          timestamp: t0,
        )).triggered,
        false,
      );

      // Slow walking (~4.3 km/h = 1.2 m/s) over 200m -> must NOT trigger
      for (int i = 1; i <= 15; i++) {
        final res = detector.evaluate(AutoTripSample(
          latitude: 21.0000 + i * 0.00014, // ~15.5m per step
          longitude: 105.8000,
          speedMps: 1.2, // 4.3 km/h
          accuracyMeters: 10.0,
          timestamp: t0.add(Duration(seconds: i * 12)),
        ));
        expect(res.triggered, false);
      }

      // Single teleport jump (300m in 2s = 540 km/h) -> must NOT trigger
      detector.reset();
      detector.evaluate(AutoTripSample(
        latitude: 21.0000,
        longitude: 105.8000,
        speedMps: 0.0,
        accuracyMeters: 8.0,
        timestamp: t0,
      ));
      expect(
        detector.evaluate(AutoTripSample(
          latitude: 21.0027,
          longitude: 105.8000,
          speedMps: 15.0,
          accuracyMeters: 10.0,
          timestamp: t0.add(const Duration(seconds: 2)),
        )).triggered,
        false,
      );

      // Genuine high-speed motorbike departure (~28 km/h = 7.8 m/s) moving > 150m across 20s -> triggers!
      detector.reset();
      detector.evaluate(AutoTripSample(
        latitude: 21.0000,
        longitude: 105.8000,
        speedMps: 0.0,
        accuracyMeters: 8.0,
        timestamp: t0,
      ));
      AutoTripTriggerResult triggeredResult = AutoTripTriggerResult.none;
      for (int i = 1; i <= 5; i++) {
        final res = detector.evaluate(AutoTripSample(
          latitude: 21.0000 + i * 0.00035, // ~39m per 5s = ~28 km/h
          longitude: 105.8000,
          speedMps: 7.8,
          accuracyMeters: 8.0,
          timestamp: t0.add(Duration(seconds: i * 5)),
        ));
        if (res.triggered) {
          triggeredResult = res;
          break;
        }
      }
      expect(triggeredResult.triggered, true);
      expect(triggeredResult.netDisplacementMeters, greaterThanOrEqualTo(150.0));
      expect(triggeredResult.departureSamples.first.latitude, closeTo(21.0000, 1e-6));
    });

    test('PlaceSearchService parses remote search results, coordinates, and infers Vietnamese categories', () {
      // 1. Direct coordinate query
      final coord = PlaceSearchService.tryParseCoordinates('21.02850, 105.85440');
      expect(coord, isNotNull);
      expect(coord!.latitude, closeTo(21.0285, 1e-5));
      expect(coord.longitude, closeTo(105.8544, 1e-5));

      // 2. Category inference from Vietnamese names
      expect(PlaceSearchService.inferCategory('Đại học Bách Khoa Hà Nội'), PinnedPlaceCategory.school);
      expect(PlaceSearchService.inferCategory('Highlands Coffee Hồ Gươm'), PinnedPlaceCategory.cafe);
      expect(PlaceSearchService.inferCategory('Công ty TNHH Phần mềm FPT'), PinnedPlaceCategory.work);
      expect(PlaceSearchService.inferCategory('Nhà hàng Phở Thìn'), PinnedPlaceCategory.restaurant);
      expect(PlaceSearchService.inferCategory('Chùa Linh Ứng Đà Nẵng'), PinnedPlaceCategory.scenic);
      expect(PlaceSearchService.inferCategory('Bãi gửi xe Bờ Hồ'), PinnedPlaceCategory.parking);

      // 3. Nominatim JSON parsing
      final nomList = PlaceSearchService.parseNominatimJson([
        {
          'place_id': 12345,
          'lat': '10.7725',
          'lon': '106.6980',
          'name': 'Chợ Bến Thành',
          'display_name': 'Chợ Bến Thành, Phường Bến Thành, Quận 1, TP. Hồ Chí Minh, Việt Nam',
          'category': 'tourism',
          'type': 'attraction',
        }
      ], refLat: 21.0285, refLng: 105.8542);
      expect(nomList.length, 1);
      expect(nomList.first.name, 'Chợ Bến Thành');
      expect(nomList.first.suggestedCategory, PinnedPlaceCategory.scenic);
      expect(nomList.first.formattedDistance, isNotNull);
    });

    test('Trip & TrackPoint persist vehicle history and mid-trip vehicle switches (motorbike default)', () {
      final t0 = DateTime(2026, 11, 24, 8, 0);
      final defaultTrip = Trip(
        id: 'trip-veh-1',
        title: 'Chuyến sáng',
        startTime: t0,
      );
      expect(defaultTrip.vehicleType, VehicleType.motorbike);
      expect(defaultTrip.vehicleSummaryLabel, 'Xe máy');

      // Switch mid-trip from motorbike -> car -> walking
      defaultTrip.recordVehicleSwitch(VehicleType.motorbike); // no-op duplicate
      defaultTrip.recordVehicleSwitch(VehicleType.car);
      defaultTrip.recordVehicleSwitch(VehicleType.walking);
      expect(defaultTrip.vehicleTypesUsed, [
        VehicleType.motorbike,
        VehicleType.car,
        VehicleType.walking,
      ]);
      expect(defaultTrip.vehicleSummaryLabel, 'Xe máy → Ô tô → Đi bộ');

      final restoredTrip = Trip.fromMap(defaultTrip.toMap());
      expect(restoredTrip.vehicleType, VehicleType.motorbike);
      expect(restoredTrip.vehicleTypesUsed, [
        VehicleType.motorbike,
        VehicleType.car,
        VehicleType.walking,
      ]);

      final ptBefore = TrackPoint(
        tripId: 'trip-veh-1',
        latitude: 21.0285,
        longitude: 105.8542,
        timestamp: t0,
      );
      final ptAfter = TrackPoint(
        tripId: 'trip-veh-1',
        latitude: 21.0300,
        longitude: 105.8560,
        timestamp: t0.add(const Duration(minutes: 5)),
        vehicleType: VehicleType.car,
      );
      expect(TrackPoint.fromMap(ptBefore.toMap()).vehicleType, VehicleType.motorbike);
      expect(TrackPoint.fromMap(ptAfter.toMap()).vehicleType, VehicleType.car);
    });

    test('PhotoDiscoveryService groups photos by same place name or nearby coordinates into folders', () {
      final baseTime = DateTime(2026, 11, 24, 10, 0);

      final photos = [
        // Same place name ("Hồ Gươm") even ~600m apart -> same folder
        Waypoint(
          id: 'p1',
          tripId: 'photo_discovery',
          name: 'Hồ Gươm',
          latitude: 21.0285,
          longitude: 105.8525,
          photoPath: '/tmp/hg1.jpg',
          timestamp: baseTime,
        ),
        Waypoint(
          id: 'p2',
          tripId: 'photo_discovery',
          name: 'hồ gươm',
          latitude: 21.0240,
          longitude: 105.8530,
          photoPath: '/tmp/hg2.jpg',
          timestamp: baseTime.add(const Duration(minutes: 10)),
        ),
        // Generic name ("Ảnh chụp • ...") within 60m of Hồ Gươm -> merged into Hồ Gươm folder
        Waypoint(
          id: 'p3',
          tripId: 'photo_discovery',
          name: 'Ảnh chụp • 24/11/2026 10:15',
          latitude: 21.0287,
          longitude: 105.8526,
          photoPath: '/tmp/hg3.jpg',
          timestamp: baseTime.add(const Duration(minutes: 15)),
        ),
        // Far-away generic photo in Đà Nẵng -> must NOT merge with generic p3
        Waypoint(
          id: 'p4',
          tripId: 'photo_discovery',
          name: 'Ảnh chụp • 24/11/2026 15:00',
          latitude: 16.0544,
          longitude: 108.2022,
          photoPath: '/tmp/dn1.jpg',
          timestamp: baseTime.add(const Duration(hours: 5)),
        ),
        // Nearby second photo in Đà Nẵng (~40m from p4) -> merged with p4
        Waypoint(
          id: 'p5',
          tripId: 'photo_discovery',
          name: 'Cầu Rồng',
          latitude: 16.0546,
          longitude: 108.2024,
          photoPath: '/tmp/dn2.jpg',
          timestamp: baseTime.add(const Duration(hours: 5, minutes: 5)),
        ),
      ];

      final folders = PhotoDiscoveryService.groupPhotosIntoFolders(photos);
      expect(folders.length, 2);

      // Sorted newest-first: Đà Nẵng folder ("Cầu Rồng", 2 photos) then Hà Nội folder ("Hồ Gươm", 3 photos)
      expect(folders[0].title, 'Cầu Rồng');
      expect(folders[0].count, 2);
      expect(folders[1].title.toLowerCase(), 'hồ gươm');
      expect(folders[1].count, 3);
    });
  });
}
