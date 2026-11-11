import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Extra bottom space on the web so floating bars sit above the hosting
/// badge (e.g. "Powered by Netlify" in the bottom-right corner).
/// Set to 0 if the badge is removed. Phones are not affected.
const double webBadgeHeight = 48;
double get webBottomGap => kIsWeb ? webBadgeHeight : 0;

// ===========================================================================
// Palettes
// ===========================================================================

/// One complete set of colours. Light and dark are tuned separately (not an
/// automatic inversion): dark uses deep navy surfaces, lifted cards, softer
/// text and slightly brighter brand colours so they keep their contrast.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.purple,
    required this.purpleSoft,
    required this.orange,
    required this.orangeSoft,
    required this.navy,
    required this.navyDark,
    required this.green,
    required this.greenSoft,
    required this.red,
    required this.redSoft,
    required this.amber,
    required this.amberSoft,
    required this.amberInk,
    required this.pinkSoft,
    required this.bg,
    required this.card,
    required this.raised,
    required this.text,
    required this.muted,
    required this.border,
    required this.shadow,
    required this.gutter,
  });

  final Brightness brightness;
  final Color purple, purpleSoft, orange, orangeSoft;

  /// Dark accent surfaces: hero card, tooltips, selected chips.
  final Color navy, navyDark;
  final Color green,
      greenSoft,
      red,
      redSoft,
      amber,
      amberSoft,
      amberInk,
      pinkSoft;

  /// Page background, card surface, raised surface (sheets/dialogs/menu bubbles).
  final Color bg, card, raised;
  final Color text, muted, border, shadow;

  /// Colour around the phone-sized layout on wide (web) screens.
  final Color gutter;

  bool get isDark => brightness == Brightness.dark;

  static const light = AppPalette(
    brightness: Brightness.light,
    purple: Color(0xFF7B3FF2),
    purpleSoft: Color(0xFFEDE5FF),
    orange: Color(0xFFFF6B35),
    orangeSoft: Color(0xFFFFEDE5),
    navy: Color(0xFF2B2D42),
    navyDark: Color(0xFF1F2033),
    green: Color(0xFF1FA968),
    greenSoft: Color(0xFFE6F6EE),
    red: Color(0xFFE53935),
    redSoft: Color(0xFFFFEBEE),
    amber: Color(0xFFFFB020),
    amberSoft: Color(0xFFFFF6E0),
    amberInk: Color(0xFFB7791F),
    pinkSoft: Color(0xFFFFF0F5),
    bg: Color(0xFFF4F5F9),
    card: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    text: Color(0xFF1E1E2D),
    muted: Color(0xFF8E8EA9),
    border: Color(0xFFEAEAF2),
    shadow: Color(0x0D1E1E2D),
    gutter: Color(0xFFE6E7EE),
  );

  static const dark = AppPalette(
    brightness: Brightness.dark,
    purple: Color(0xFF9D6BFF),
    purpleSoft: Color(0xFF2A2347),
    orange: Color(0xFFFF7E4D),
    orangeSoft: Color(0xFF3A2620),
    navy: Color(0xFF34375A),
    navyDark: Color(0xFF242641),
    green: Color(0xFF3DD68C),
    greenSoft: Color(0xFF173528),
    red: Color(0xFFFF5C5C),
    redSoft: Color(0xFF3A1D22),
    amber: Color(0xFFFFC14D),
    amberSoft: Color(0xFF3A3020),
    amberInk: Color(0xFFFFC14D),
    pinkSoft: Color(0xFF3A1F2E),
    bg: Color(0xFF0F1020),
    card: Color(0xFF1A1B2E),
    raised: Color(0xFF23253B),
    text: Color(0xFFEDEDF7),
    muted: Color(0xFF9A9BB8),
    border: Color(0xFF2C2E48),
    shadow: Color(0x40000000),
    gutter: Color(0xFF080812),
  );
}

/// The colours of the CURRENT mode. Every widget reads these, and the whole
/// tree is rebuilt when the mode changes (see [ThemeSwitchScope]).
class AppColors {
  static AppPalette _p = AppPalette.light;
  static AppPalette get palette => _p;
  static bool get isDark => _p.isDark;

  static Color get purple => _p.purple;
  static Color get purpleLight => _p.purpleSoft;
  static Color get orange => _p.orange;
  static Color get orangeLight => _p.orangeSoft;
  static Color get navy => _p.navy;
  static Color get navyDark => _p.navyDark;
  static Color get green => _p.green;
  static Color get greenSoft => _p.greenSoft;
  static Color get red => _p.red;
  static Color get redSoft => _p.redSoft;
  static Color get amber => _p.amber;
  static Color get amberSoft => _p.amberSoft;
  static Color get amberInk => _p.amberInk;
  static Color get pinkSoft => _p.pinkSoft;
  static Color get bg => _p.bg;
  static Color get card => _p.card;
  static Color get raised => _p.raised;
  static Color get text => _p.text;
  static Color get muted => _p.muted;
  static Color get border => _p.border;
  static Color get shadow => _p.shadow;
  static Color get gutter => _p.gutter;
}

/// In dark mode, raises very dark brand colours (e.g. Visa navy) to a
/// readable lightness; light mode returns the colour unchanged.
Color liftForDark(Color c) {
  if (!AppColors.isDark) return c;
  final hsl = HSLColor.fromColor(c);
  return hsl.lightness < 0.55
      ? hsl
            .withLightness(0.62)
            .withSaturation((hsl.saturation * 0.9).clamp(0, 1))
            .toColor()
      : c;
}

// ===========================================================================
// Mode setting (System / Light / Dark), saved on the device
// ===========================================================================

class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final instance = ThemeController._();

  static const _key = 'themeMode';
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _mode = ThemeMode.values.firstWhere(
        (m) => m.name == p.getString(_key),
        orElse: () => ThemeMode.system,
      );
    } catch (e) {
      debugPrint('Theme load failed: $e');
    }
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, m.name);
    } catch (e) {
      debugPrint('Theme save failed: $e');
    }
  }

  /// Quick toggle (home screen): flips between light and dark.
  Future<void> toggle(Brightness current) =>
      setMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}

/// Put inside MaterialApp.builder. Switches [AppColors] to the active
/// brightness and rebuilds every widget below (keeping all state – open
/// screens, scroll positions, forms) so nothing keeps stale colours.
class ThemeSwitchScope extends StatefulWidget {
  const ThemeSwitchScope({super.key, required this.child});
  final Widget child;

  @override
  State<ThemeSwitchScope> createState() => _ThemeSwitchScopeState();
}

class _ThemeSwitchScopeState extends State<ThemeSwitchScope> {
  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final p = b == Brightness.dark ? AppPalette.dark : AppPalette.light;
    if (!identical(AppColors._p, p)) {
      AppColors._p = p;
      void rebuild(Element e) {
        e.markNeedsBuild();
        e.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: ColoredBox(color: p.gutter, child: widget.child),
    );
  }
}

// ===========================================================================
// ThemeData
// ===========================================================================

class AppTheme {
  static ThemeData light() => build(AppPalette.light);
  static ThemeData dark() => build(AppPalette.dark);

  static ThemeData build(AppPalette p) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: p.purple,
        brightness: p.brightness,
        primary: p.purple,
        secondary: p.orange,
        surface: p.card,
        error: p.red,
      ),
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      dividerColor: p.border,
    );
    final text = GoogleFonts.poppinsTextTheme(base.textTheme)
        .apply(bodyColor: p.text, displayColor: p.text);
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );
    return base.copyWith(
      textTheme: text,
      iconTheme: IconThemeData(color: p.text),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: p.text,
        systemOverlayStyle: p.isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: p.text,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.isDark ? p.raised : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: border(p.border),
        enabledBorder: border(p.border),
        focusedBorder: border(p.purple, 1.6),
        errorBorder: border(p.red),
        focusedErrorBorder: border(p.red, 1.6),
        labelStyle: TextStyle(color: p.muted),
        hintStyle: TextStyle(color: p.muted),
        prefixIconColor: p.muted,
        suffixIconColor: p.muted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.purple,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.border,
          disabledForegroundColor: p.muted,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          minimumSize: const Size.fromHeight(54),
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.purple),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.card,
        selectedColor: p.purpleSoft,
        side: BorderSide(color: p.border),
        labelStyle: TextStyle(color: p.text),
        secondaryLabelStyle: TextStyle(color: p.text),
        checkmarkColor: p.purple,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : p.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.purple : p.border,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.purple : p.card,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : p.text,
          ),
          side: WidgetStateProperty.all(BorderSide(color: p.border)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.raised,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: p.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.raised,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: p.text,
        ),
        contentTextStyle: GoogleFonts.poppins(fontSize: 14, color: p.text),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.raised,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: p.purple,
        headerForegroundColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.isDark ? p.raised : p.navy,
        contentTextStyle: GoogleFonts.poppins(
          color: p.isDark ? p.text : Colors.white,
        ),
        actionTextColor: p.isDark ? p.purple : const Color(0xFFC6B0FF),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.raised,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: p.muted.withValues(alpha: 0.5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.purple),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.isDark ? p.raised : p.navy,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
          color: p.isDark ? p.text : Colors.white,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Soft card used across the app (white in light mode, lifted navy in dark).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.gradient,
    this.onTap,
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? AppColors.card) : null,
        gradient: gradient,
        borderRadius: r,
        // Dark mode: a hairline border instead of a (barely visible) shadow.
        border: AppColors.isDark && gradient == null
            ? Border.all(color: AppColors.border.withValues(alpha: 0.6))
            : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: r,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
