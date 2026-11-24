import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/pinned_place.dart';
import '../models/stay_point.dart';
import '../models/track_point.dart';
import '../models/trip.dart';
import '../models/waypoint.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'journey_discovery.db');

    return await openDatabase(
      path,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE trips (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        total_distance REAL DEFAULT 0.0,
        new_distance REAL DEFAULT 0.0,
        duration_seconds INTEGER DEFAULT 0,
        max_speed REAL DEFAULT 0.0,
        avg_speed REAL DEFAULT 0.0,
        point_count INTEGER DEFAULT 0,
        start_address TEXT,
        end_address TEXT,
        is_completed INTEGER DEFAULT 0,
        vehicle_type INTEGER DEFAULT 0,
        vehicle_types TEXT DEFAULT '0'
      )
    ''');

    await db.execute('''
      CREATE TABLE track_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL DEFAULT 0.0,
        speed REAL DEFAULT 0.0,
        accuracy REAL DEFAULT 0.0,
        timestamp TEXT NOT NULL,
        vehicle_type INTEGER DEFAULT 0,
        FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE waypoints (
        id TEXT PRIMARY KEY,
        trip_id TEXT NOT NULL,
        name TEXT NOT NULL,
        note TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        timestamp TEXT NOT NULL,
        photo_path TEXT,
        FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE stay_points (
        id TEXT PRIMARY KEY,
        trip_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        arrival_time TEXT NOT NULL,
        departure_time TEXT NOT NULL,
        address TEXT,
        status TEXT NOT NULL,
        confirmed_name TEXT,
        note TEXT,
        FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE pinned_places (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        radius_meters INTEGER DEFAULT 50,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_track_points_trip_id ON track_points(trip_id)');
    await db.execute('CREATE INDEX idx_waypoints_trip_id ON waypoints(trip_id)');
    await db.execute('CREATE INDEX idx_stay_points_trip_id ON stay_points(trip_id)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS stay_points (
          id TEXT PRIMARY KEY,
          trip_id TEXT NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          arrival_time TEXT NOT NULL,
          departure_time TEXT NOT NULL,
          address TEXT,
          status TEXT NOT NULL,
          confirmed_name TEXT,
          note TEXT,
          FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stay_points_trip_id ON stay_points(trip_id)');
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE waypoints ADD COLUMN photo_path TEXT');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE trips ADD COLUMN new_distance REAL DEFAULT 0.0');
      } catch (_) {}
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pinned_places (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          category TEXT NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          radius_meters INTEGER DEFAULT 50,
          note TEXT,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE trips ADD COLUMN vehicle_type INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE trips ADD COLUMN vehicle_types TEXT DEFAULT '0'");
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE track_points ADD COLUMN vehicle_type INTEGER DEFAULT 0');
      } catch (_) {}
    }
  }

  // --- Trip Operations ---

  Future<int> insertTrip(Trip trip) async {
    final db = await database;
    return await db.insert(
      'trips',
      trip.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateTrip(Trip trip) async {
    final db = await database;
    return await db.update(
      'trips',
      trip.toMap(),
      where: 'id = ?',
      whereArgs: [trip.id],
    );
  }

  Future<void> updateTripsNewDistancesBatch(Map<String, double> updates) async {
    if (updates.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    updates.forEach((tripId, newDist) {
      batch.update(
        'trips',
        {'new_distance': newDist},
        where: 'id = ?',
        whereArgs: [tripId],
      );
    });
    await batch.commit(noResult: true);
  }

  Future<int> deleteTrip(String tripId) async {
    final db = await database;
    await db.delete('track_points', where: 'trip_id = ?', whereArgs: [tripId]);
    await db.delete('waypoints', where: 'trip_id = ?', whereArgs: [tripId]);
    await db.delete('stay_points', where: 'trip_id = ?', whereArgs: [tripId]);
    return await db.delete('trips', where: 'id = ?', whereArgs: [tripId]);
  }

  Future<Trip?> getTrip(String tripId) async {
    final db = await database;
    final results = await db.query('trips', where: 'id = ?', whereArgs: [tripId]);
    if (results.isEmpty) return null;

    final points = await getPointsForTrip(tripId);
    final waypoints = await getWaypointsForTrip(tripId);
    return Trip.fromMap(results.first, points: points, waypoints: waypoints);
  }

  Future<List<Trip>> getAllTrips() async {
    final db = await database;
    final results = await db.query('trips', orderBy: 'start_time DESC');
    return results.map((map) => Trip.fromMap(map)).toList();
  }

  Future<List<Trip>> getTripsByMonth(int year, int month) async {
    final db = await database;
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 1).toIso8601String();

    final results = await db.query(
      'trips',
      where: 'start_time >= ? AND start_time < ?',
      whereArgs: [start, end],
      orderBy: 'start_time DESC',
    );
    return results.map((map) => Trip.fromMap(map)).toList();
  }

  // --- TrackPoint Operations ---

  Future<int> insertTrackPoint(TrackPoint point) async {
    final db = await database;
    return await db.insert('track_points', point.toMap());
  }

  Future<void> insertTrackPointsBatch(List<TrackPoint> points) async {
    if (points.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final p in points) {
      batch.insert('track_points', p.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<TrackPoint>> getPointsForTrip(String tripId) async {
    final db = await database;
    final results = await db.query(
      'track_points',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'id ASC',
    );
    return results.map((map) => TrackPoint.fromMap(map)).toList();
  }

  Future<Map<String, List<TrackPoint>>> getAllExploredRoutes() async {
    final db = await database;
    final results = await db.query('track_points', orderBy: 'trip_id ASC, id ASC');
    final Map<String, List<TrackPoint>> routes = {};
    for (final row in results) {
      final point = TrackPoint.fromMap(row);
      routes.putIfAbsent(point.tripId, () => []).add(point);
    }
    return routes;
  }

  // --- Waypoint Operations ---

  Future<int> insertWaypoint(Waypoint waypoint) async {
    final db = await database;
    return await db.insert(
      'waypoints',
      waypoint.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Waypoint>> getWaypointsForTrip(String tripId) async {
    final db = await database;
    final results = await db.query(
      'waypoints',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'timestamp ASC',
    );
    return results.map((map) => Waypoint.fromMap(map)).toList();
  }

  Future<List<Waypoint>> getAllWaypoints() async {
    final db = await database;
    final results = await db.query('waypoints', orderBy: 'timestamp DESC');
    return results.map((map) => Waypoint.fromMap(map)).toList();
  }

  Future<int> getWaypointCountForMonth(int year, int month) async {
    final db = await database;
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 1).toIso8601String();

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM waypoints WHERE timestamp >= ? AND timestamp < ?',
      [start, end],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Waypoint>> getPhotoWaypoints() async {
    final db = await database;
    final results = await db.query(
      'waypoints',
      where: 'photo_path IS NOT NULL AND photo_path != ""',
      orderBy: 'timestamp DESC',
    );
    return results.map((map) => Waypoint.fromMap(map)).toList();
  }

  Future<int> deleteWaypoint(String id) async {
    final db = await database;
    return await db.delete('waypoints', where: 'id = ?', whereArgs: [id]);
  }

  // --- StayPoint Operations (Tự động phát hiện điểm dừng) ---

  Future<int> insertStayPoint(StayPoint stayPoint) async {
    final db = await database;
    return await db.insert(
      'stay_points',
      stayPoint.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateStayPoint(StayPoint stayPoint) async {
    final db = await database;
    return await db.update(
      'stay_points',
      stayPoint.toMap(),
      where: 'id = ?',
      whereArgs: [stayPoint.id],
    );
  }

  Future<List<StayPoint>> getPendingStayPoints() async {
    final db = await database;
    final results = await db.query(
      'stay_points',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'arrival_time DESC',
    );
    return results.map((map) => StayPoint.fromMap(map)).toList();
  }

  Future<int> deleteStayPoint(String id) async {
    final db = await database;
    return await db.delete('stay_points', where: 'id = ?', whereArgs: [id]);
  }

  // --- PinnedPlace Operations (Địa điểm ghim trên bản đồ) ---

  Future<int> insertPinnedPlace(PinnedPlace place) async {
    final db = await database;
    return await db.insert(
      'pinned_places',
      place.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updatePinnedPlace(PinnedPlace place) async {
    final db = await database;
    return await db.update(
      'pinned_places',
      place.toMap(),
      where: 'id = ?',
      whereArgs: [place.id],
    );
  }

  Future<int> deletePinnedPlace(String id) async {
    final db = await database;
    return await db.delete('pinned_places', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<PinnedPlace>> getAllPinnedPlaces() async {
    final db = await database;
    final results = await db.query('pinned_places', orderBy: 'created_at DESC');
    return results.map((map) => PinnedPlace.fromMap(map)).toList();
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('track_points');
    await db.delete('waypoints');
    await db.delete('stay_points');
    await db.delete('trips');
  }

  /// Export 100% complete database to JSON structure for direct personal Google Drive backup
  Future<Map<String, dynamic>> exportFullDatabaseJson() async {
    final db = await database;
    final trips = await db.query('trips');
    final trackPoints = await db.query('track_points');
    final waypoints = await db.query('waypoints');
    final stayPoints = await db.query('stay_points');
    final pinnedPlaces = await db.query('pinned_places');

    return {
      'app': 'BanDoHanhTrinh',
      'version': '1.0.0',
      'exported_at': DateTime.now().toIso8601String(),
      'trips': trips,
      'track_points': trackPoints,
      'waypoints': waypoints,
      'stay_points': stayPoints,
      'pinned_places': pinnedPlaces,
    };
  }

  /// Restore database from JSON backup file
  Future<void> importDatabaseJson(Map<String, dynamic> data) async {
    final db = await database;
    final batch = db.batch();

    if (data['trips'] is List) {
      for (final t in data['trips']) {
        batch.insert('trips', Map<String, dynamic>.from(t), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    if (data['track_points'] is List) {
      for (final p in data['track_points']) {
        batch.insert('track_points', Map<String, dynamic>.from(p), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    if (data['waypoints'] is List) {
      for (final w in data['waypoints']) {
        batch.insert('waypoints', Map<String, dynamic>.from(w), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    if (data['stay_points'] is List) {
      for (final s in data['stay_points']) {
        batch.insert('stay_points', Map<String, dynamic>.from(s), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    if (data['pinned_places'] is List) {
      for (final pp in data['pinned_places']) {
        batch.insert('pinned_places', Map<String, dynamic>.from(pp), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    await batch.commit(noResult: true);
  }
}
