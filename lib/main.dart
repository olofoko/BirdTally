import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'providers/home_provider.dart';
import 'screens/home/home_screen.dart';
import 'services/app_settings.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('sv_SE');
  await AppSettings.instance.load();
  // Portrait only — field use, one-handed tally.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://0effb38466838872691a2f96a7227e08@o4511206253395968.ingest.de.sentry.io/4511206255689808';
      // Set tracesSampleRate to 1.0 to capture 100% of transactions for tracing.
      // We recommend adjusting this value in production.
      options.tracesSampleRate = 1.0;
    },
    appRunner: () => runApp(SentryWidget(child: const BirdTallyApp())),
  );
}

class BirdTallyApp extends StatelessWidget {
  const BirdTallyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeProvider()),
      ],
      child: MaterialApp(
        title: 'BirdTally',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        navigatorObservers: [SentryNavigatorObserver()],
        home: const HomeScreen(),
      ),
    );
  }

  ThemeData _buildTheme() {
    const seedColor = Color(0xFF2E7D32); // forest green

    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      // Large touch targets for gloved/cold-weather field use.
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    );
  }
}
