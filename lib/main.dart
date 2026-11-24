import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'providers/map_settings_provider.dart';
import 'providers/tracking_provider.dart';
import 'providers/trip_provider.dart';
import 'screens/main_screen.dart';
import 'services/offline_map_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };
  try {
    await initializeDateFormatting('vi', null);
    await initializeDateFormatting('vi_VN', null);
  } catch (_) {}
  try {
    await OfflineMapService().init();
  } catch (_) {}
  runApp(const BanDoHanhTrinhApp());
}

class BanDoHanhTrinhApp extends StatelessWidget {
  const BanDoHanhTrinhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MapSettingsProvider()),
        ChangeNotifierProvider(create: (_) => TrackingProvider()),
        ChangeNotifierProvider(create: (_) => TripProvider()),
      ],
      child: MaterialApp(
        title: 'Bản Đồ Hành Trình',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const MainScreen(),
      ),
    );
  }
}
