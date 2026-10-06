// ============================================================
// lib/theme/app_theme.dart
//
// Day 1, Item 2 — centralized design tokens (Standard 6).
//
// WHY THIS FILE EXISTS:
// A grep across the current codebase found 500+ individual hardcoded
// Color(0xFF...) literals across 9 screens, 13 distinct gradient pairs
// repeated inconsistently, and 11 different BorderRadius.circular()
// values where the visual intent was clearly only 4-5 distinct sizes.
// This file is the single source of truth those should all point to.
//
// MIGRATION STRATEGY (deliberately incremental — see chat for why):
// This file is additive today. It does not yet replace the inline
// Color(0xFF667EEA) literals in every screen — that is a separate,
// larger migration tracked on the roadmap, done screen-by-screen so
// each migration can be tested in isolation rather than changing 9
// screens in one irreversible pass. New code from this point forward
// MUST use AppColors/AppGradients/AppRadius/AppSpacing/AppText below
// instead of inline literals (Standard 3 — architectural consistency
// applies to all new work immediately, even before the old work is
// migrated).
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ────────────────────────────────────────────────────────────────────────
// COLORS
// ────────────────────────────────────────────────────────────────────────
//
// Naming reflects WHAT the color means in this app, not just its hex
// value — e.g. `primary` not `purple667EEA`. This is what lets the
// eventual Phase 2 light-theme toggle (item 2.7 on the roadmap) swap
// values later without renaming every call site across the app.

class AppColors {
  AppColors._(); // static-only, never instantiated

  // ── Brand / primary actions (Manager-facing, the most common accent) ──
  // Source: Color(0xFF667EEA) appeared 88 times — the single most
  // repeated literal in the entire codebase.
  static const Color purpleDeep  = Color(0xFF4A148C);
  static const Color pink        = Color(0xFFE91E8C);
  static const Color flutterBlue = Color(0xFF4FC3F7);
  static const Color gold        = Color(0xFFFFE66D);
  static const Color goldDeep    = Color(0xFFFFB347);
  static const primary       = Color(0xFF667EEA);
  static const primaryDeep   = Color(0xFF764BA2); // pairs with primary in gradients

  // ── Secondary brand accents, by role/context ──────────────────────────
  static const teal          = Color(0xFF11998E); // success / employee accents
  static const tealLight     = Color(0xFF38EF7D); // pairs with teal in gradients
  static const indigo        = Color(0xFF4776E6); // manager-role badges
  static const indigoLight   = Color(0xFF8E54E9); // pairs with indigo
  static const magenta       = Color(0xFF9C27B0); // customer-facing accents
  static const magentaLight  = Color(0xFFE91E8C); // pairs with magenta
  static const magentaPale   = Color(0xFFCE93D8); // customer text-on-dark accent

  // ── Status colors (semantic — used for SaleStatus, stock levels, etc.) ─
  static const success       = Color(0xFF38EF7D);
  static const warning       = Color(0xFFFFB347);
  static const danger        = Color(0xFFFF6B6B); // 88 occurrences — second most repeated
  static const dangerLight   = Color(0xFFFFE66D); // pairs with danger in gradients
  static const info          = Color(0xFF667EEA); // alias of primary, named for clarity at call sites

  // ── Surface colors (the dark theme's backgrounds, in elevation order) ──
  // Source: these 3 together account for 137 occurrences — clearly the
  // app's actual background/surface/card system, just never named as one.
  static const background    = Color(0xFF0F1226); // app background (lowest elevation)
  static const surface       = Color(0xFF1A1F36); // card/sheet background (mid elevation)
  static const surfaceRaised = Color(0xFF252B48); // input fields, nested surfaces (highest elevation)

  // ── Splash/auth screen gradient (distinct from in-app surfaces) ───────
  static const authBgStart   = Color(0xFF0A0E21);
  static const authBgEnd     = Color(0xFF1A1F3C);
  static const authBgDeepest = Color(0xFF0D1117); // login_screen.dart's 3rd gradient stop

  // ── Text on dark surfaces ──────────────────────────────────────────────
  static const textPrimary   = Colors.white;
  static const textSecondary = Colors.white70;
  static const textTertiary  = Colors.white54;
  static const textDisabled  = Colors.white38;
  static const textFaint     = Colors.white24;

  // ── Borders / outlines on dark surfaces ────────────────────────────────
  static const border        = Colors.white12; // subtle outlines, disabled fills

  // ── Role-badge colors (mirrors AppRole enum from rbac_model.dart) ─────
  // Centralizing this mapping in one place means a role's color is
  // defined ONCE, not redefined per-screen wherever a role badge renders.
  static const roleManager   = indigo;
  static const roleEmployee  = teal;
  static const roleCustomer  = magenta;
}

// ────────────────────────────────────────────────────────────────────────
// GRADIENTS
// ────────────────────────────────────────────────────────────────────────
//
// The 13 gradient pairs found in the grep collapse to these named,
// reusable LinearGradients. Each one is documented with WHERE it was
// found being used, so migrating a screen later is a lookup, not a
// guess.

class AppGradients {
  AppGradients._();

  // Found 8x — the most common gradient in the app. Primary buttons,
  // Manager-role badges, splash/login logo circle.
  static const primary = LinearGradient(
    colors: [AppColors.primary, AppColors.primaryDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Add in AppGradients class
static const LinearGradient employeeHeader = LinearGradient(
  begin: Alignment.topLeft, end: Alignment.bottomRight,
  colors: [Color(0xFF0B4D3B), Color(0xFF11998E)],
);
static const LinearGradient customerHomeHeader = LinearGradient(
  begin: Alignment.topLeft, end: Alignment.bottomRight,
  colors: [Color(0xFF4A148C), Color(0xFF880E4F)],
);
static const LinearGradient customerProfileHeader = LinearGradient(
  begin: Alignment.topLeft, end: Alignment.bottomRight,
  colors: [Color(0xFF4A148C), Color(0xFF1A1F36)],
);
static const LinearGradient settingsHeader = LinearGradient(
  begin: Alignment.topLeft, end: Alignment.bottomRight,
  colors: [Color(0xFF1A237E), Color(0xFF0D47A1)],
);

  // Found 4x — customer-facing accents (Customer Dashboard avatar,
  // buy-now button, customer role badges).
  static const customer = LinearGradient(
    colors: [AppColors.magenta, AppColors.magentaLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Found 4x — success/teal accents (Employee role badges, completed
  // status indicators).
  static const success = LinearGradient(
    colors: [AppColors.teal, AppColors.tealLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Found 3x — Manager-role badge variant (Employee screen specifically
  // used a slightly different indigo pairing than the primary gradient).
  static const manager = LinearGradient(
    colors: [AppColors.indigo, AppColors.indigoLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Found 2x — danger/destructive actions, revenue highlight cards.
  static const danger = LinearGradient(
    colors: [AppColors.danger, AppColors.dangerLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Found in Reports screen specifically — pink-to-red, used for
  // chart accents distinct from the danger gradient above.
  static const reportAccent = LinearGradient(
    colors: [Color(0xFFF093FB), Color(0xFFF5576C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // App-wide background gradient (Splash, Login, surface backgrounds).
  static const background = LinearGradient(
    colors: [AppColors.surface, AppColors.background],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Auth-screen-specific background (slightly different from in-app
  // background — darker, used only on Login/Splash).
  static const authBackground = LinearGradient(
    colors: [AppColors.authBgStart, AppColors.authBgEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Login screen specifically uses a 3-stop variant of the auth
  // background (found only in login_screen.dart, nowhere else) — kept
  // as its own token rather than force-fitting it into the 2-stop
  // authBackground above, since merging them would silently change
  // the login screen's actual visual gradient.
  static const authBackgroundDeep = LinearGradient(
    colors: [AppColors.authBgStart, AppColors.authBgEnd, AppColors.authBgDeepest],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ────────────────────────────────────────────────────────────────────────
// RADIUS
// ────────────────────────────────────────────────────────────────────────
//
// 11 distinct values found, collapsed to 5 deliberate sizes. Mapping
// shown in comments so a screen migration knows which old value maps
// to which new token.

class AppRadius {
  AppRadius._();

  static const sm   = 8.0;   // was: 6, 7, 8           → small chips, tags
  static const md   = 12.0;  // was: 10, 12             → buttons, input fields
  static const lg   = 16.0;  // was: 14, 16              → cards, bottom-sheet content
  static const xl   = 20.0;  // was: 18, 20              → modals, large cards
  static const full = 999.0; // was: 24 and any "pill" shape → fully rounded chips/pills

  // Found separately during screen migration: a bottom-sheet "drag
  // handle" pill (small 40x4 bar) using BorderRadius.circular(2),
  // repeated identically across 8 files. Distinct from the sizes above
  // — this is specifically a thin-pill radius, not a generic small size.
  static const handle = 2.0;

  static BorderRadius get smRadius     => BorderRadius.circular(sm);
  static BorderRadius get mdRadius     => BorderRadius.circular(md);
  static BorderRadius get lgRadius     => BorderRadius.circular(lg);
  static BorderRadius get xlRadius     => BorderRadius.circular(xl);
  static BorderRadius get fullRadius   => BorderRadius.circular(full);
  static BorderRadius get handleRadius => BorderRadius.circular(handle);
}

// ────────────────────────────────────────────────────────────────────────
// SPACING
// ────────────────────────────────────────────────────────────────────────
//
// Not found via grep (spacing was reasonably consistent already via
// repeated SizedBox(height: 8/12/16/24) patterns) but formalized here
// so new code has a named scale instead of guessing a number.

class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

// ────────────────────────────────────────────────────────────────────────
// TYPOGRAPHY
// ────────────────────────────────────────────────────────────────────────
//
// Every screen calls GoogleFonts.poppins(...) inline with hand-picked
// size/weight/color per call site. These named styles cover the actual
// patterns observed (headline, title, body, caption, button label) so
// new code picks a named style instead of re-deciding size/weight each
// time.

class AppText {
  AppText._();

  static TextStyle headline({Color color = AppColors.textPrimary}) =>
      GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, color: color);

  static TextStyle title({Color color = AppColors.textPrimary}) =>
      GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: color);

  static TextStyle subtitle({Color color = AppColors.textSecondary}) =>
      GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: color);

  static TextStyle body({Color color = AppColors.textPrimary}) =>
      GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400, color: color);

  static TextStyle caption({Color color = AppColors.textTertiary}) =>
      GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400, color: color);

  static TextStyle buttonLabel({Color color = AppColors.textPrimary}) =>
      GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: color);

  static TextStyle badge({Color color = AppColors.textPrimary}) =>
      GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: color);
}

// ────────────────────────────────────────────────────────────────────────
// MATERIAL THEME DATA
// ────────────────────────────────────────────────────────────────────────
//
// Wires the tokens above into a real ThemeData so MaterialApp can use
// it directly, and so Phase 2's light-theme toggle has a clear second
// ThemeData to add alongside this one later.

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.primaryDeep,
          surface: AppColors.surface,
          error: AppColors.danger,
        ),
        textTheme: TextTheme(
          headlineMedium: AppText.headline(),
          titleMedium: AppText.title(),
          bodyMedium: AppText.body(),
          bodySmall: AppText.caption(),
        ),
        useMaterial3: true,
      );
}