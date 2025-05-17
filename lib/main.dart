import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:google_fonts/google_fonts.dart';

import 'widgets/tabs_navigation.dart';

var kColorScheme = ColorScheme.fromSeed(
  seedColor: const Color.fromARGB(255, 0, 255, 0),
);

var kDarkColorScheme = ColorScheme.fromSeed(
  brightness: Brightness.dark,
  seedColor: const Color.fromARGB(255, 0, 55, 0),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]).then(
    (_) => initializeDateFormatting('pl_PL', null).then(
      (_) => runApp(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          darkTheme: ThemeData.dark().copyWith(
            colorScheme: kDarkColorScheme,
            appBarTheme: const AppBarTheme().copyWith(
              backgroundColor: kDarkColorScheme.primaryContainer,
              foregroundColor: kDarkColorScheme.onPrimaryContainer,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: kDarkColorScheme.primaryContainer,
                foregroundColor: kDarkColorScheme.onPrimaryContainer,
              ),
            ),
          ),
          theme: ThemeData().copyWith(
            colorScheme: kColorScheme,
            appBarTheme: const AppBarTheme().copyWith(
              backgroundColor: kColorScheme.onPrimaryContainer,
              foregroundColor: kColorScheme.primaryContainer,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: kColorScheme.primaryContainer,
              ),
            ),
            textTheme: GoogleFonts.latoTextTheme(
              ThemeData().textTheme,
            ).copyWith(
              titleLarge: TextStyle(
                color: kColorScheme.onPrimaryContainer,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          home: Scaffold(
            body: navigationBody[TabsNavigation.currentPageIndex]),
          routes: navigationRoutes,
          themeMode: ThemeMode.system,
        ),
      ),
    ),
  );
}
