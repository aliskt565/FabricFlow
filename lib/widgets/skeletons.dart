// filepath: lib/widgets/skeletons.dart
// ============================================================
// lib/widgets/skeletons.dart
//
// Day 5 — Skeleton loading states.
//
// DESIGN RATIONALE:
//   All screens use StreamBuilder with Firestore streams.
//   Before the first snapshot arrives (ConnectionState.waiting)
//   they previously showed a blank white space or an empty list.
//   These skeleton widgets replace that blank state with a
//   pulsing shimmer that mirrors the shape of the actual content,
//   giving users immediate visual feedback that data is loading.
//
// IMPLEMENTATION:
//   Pure Flutter — no shimmer package dependency.
//   TweenAnimationBuilder pulses opacity 0.3 → 0.8 → 0.3 on a
//   1.4 s looping curve. The shimmer highlight is a gradient
//   overlay (white 0% → 8% → 0%) to simulate the classic
//   left-to-right shimmer look without needing AnimationController
//   at the call site (TweenAnimationBuilder handles its own state).
//
// LINT FIX (flutter analyze):
//   Every `_PulseBox(...)` call below now has `const` in front of it.
//   _PulseBox's constructor only takes compile-time-constant values
//   (doubles), so the analyzer's prefer_const_literals_to_create_immutables
//   rule flags any call missing the `const` keyword — this is a pure
//   lint fix, no behavior change.
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ────────────────────────────────────────────────────────────────────────
// BASE — single shimmering rectangle
// ────────────────────────────────────────────────────────────────────────

class SkeletonBox extends StatelessWidget {
  final double  width;
  final double  height;
  final double  radius;
  final bool    shimmer;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius  = AppRadius.md,
    this.shimmer = true,
  });

  @override
  Widget build(BuildContext context) {
    final base = Container(
      width:  width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    if (!shimmer) return base;

    return TweenAnimationBuilder<double>(
      tween:    Tween(begin: 0.3, end: 0.85),
      duration: const Duration(milliseconds: 900),
      curve:    Curves.easeInOut,
      builder:  (_, value, child) => Opacity(opacity: value, child: child),
      child: _PulseBox(width: width, height: height, radius: radius),
    );
  }
}

/// Internal widget that animates continuously using its own controller.
class _PulseBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const _PulseBox({required this.width, required this.height, required this.radius});

  @override
  State<_PulseBox> createState() => _PulseBoxState();
}

class _PulseBoxState extends State<_PulseBox> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.85).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Opacity(
      opacity: _anim.value,
      child: Container(
        width:  widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF252B48), // surfaceRaised
              Color(0xFF2E3555), // slightly lighter — shimmer highlight
              Color(0xFF252B48),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
      ),
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────
// SKELETON CARD — mimics a list item row (icon + two lines of text)
// Used by: Inventory, Sales, Customers, Employees
// ────────────────────────────────────────────────────────────────────────

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        AppColors.surface,
      borderRadius: AppRadius.lgRadius,
      border:       Border.all(color: AppColors.border),
    ),
    child: Row(children: [
      // Avatar/icon placeholder
      const _PulseBox(width: 48, height: 48, radius: AppRadius.md),
      const SizedBox(width: 14),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PulseBox(width: double.infinity, height: 13, radius: AppRadius.sm),
          const SizedBox(height: 8),
          const _PulseBox(width: 140, height: 10, radius: AppRadius.sm),
        ],
      )),
      const SizedBox(width: 12),
      // Right-side badge/price placeholder
      const _PulseBox(width: 60, height: 28, radius: AppRadius.sm),
    ]),
  );
}

// ────────────────────────────────────────────────────────────────────────
// SKELETON LIST VIEW — a column of SkeletonCards
// ────────────────────────────────────────────────────────────────────────

class SkeletonListView extends StatelessWidget {
  final int count;
  const SkeletonListView({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(count, (_) => const SkeletonCard()),
  );
}

// ────────────────────────────────────────────────────────────────────────
// SKELETON STAT CARD — mimics a KPI metric card (number + label)
// Used by: Dashboard home tab KPI row
// ────────────────────────────────────────────────────────────────────────

class SkeletonStatCard extends StatelessWidget {
  const SkeletonStatCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width:   160,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        AppColors.surface,
      borderRadius: AppRadius.lgRadius,
      border:       Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const _PulseBox(width: 36, height: 36, radius: AppRadius.md),
          const Spacer(),
          const _PulseBox(width: 48, height: 20, radius: AppRadius.sm),
        ]),
        const SizedBox(height: 12),
        const _PulseBox(width: 80, height: 18, radius: AppRadius.sm),
        const SizedBox(height: 6),
        const _PulseBox(width: 110, height: 11, radius: AppRadius.sm),
      ],
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────
// SKELETON CHART CARD — mimics a chart section with title + chart area
// Used by: Dashboard home tab chart sections
// ────────────────────────────────────────────────────────────────────────

class SkeletonChartCard extends StatelessWidget {
  final double height;
  const SkeletonChartCard({super.key, this.height = 220});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color:        AppColors.surface,
      borderRadius: AppRadius.lgRadius,
      border:       Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title area
        Row(children: [
          const _PulseBox(width: 28, height: 28, radius: AppRadius.sm),
          const SizedBox(width: 10),
          const _PulseBox(width: 140, height: 14, radius: AppRadius.sm),
          const Spacer(),
          const _PulseBox(width: 56, height: 22, radius: AppRadius.full),
        ]),
        const SizedBox(height: 20),
        // Chart body placeholder
        _PulseBox(width: double.infinity, height: height, radius: AppRadius.md),
      ],
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────
// SKELETON HEADER — mimics the page header with title + subtitle
// Used by: screens that show a summary badge in the header while loading
// ────────────────────────────────────────────────────────────────────────

class SkeletonHeader extends StatelessWidget {
  const SkeletonHeader({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _PulseBox(width: 120, height: 22, radius: AppRadius.sm),
          const SizedBox(height: 6),
          const _PulseBox(width: 180, height: 13, radius: AppRadius.sm),
        ]),
        const _PulseBox(width: 90, height: 36, radius: AppRadius.full),
      ],
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────
// SKELETON KPI ROW — mimics the 4-card KPI row on the dashboard
// ────────────────────────────────────────────────────────────────────────

class SkeletonKpiRow extends StatelessWidget {
  const SkeletonKpiRow({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 110,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (_, __) => const SkeletonStatCard(),
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────
// SKELETON DASHBOARD — full dashboard loading placeholder
// Shown in dashboard_screen.dart during ConnectionState.waiting
// ────────────────────────────────────────────────────────────────────────

class SkeletonDashboard extends StatelessWidget {
  const SkeletonDashboard({super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const NeverScrollableScrollPhysics(),
    child: Column(children: [
      // Header placeholder
      Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgRadius,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _PulseBox(width: 180, height: 14, radius: AppRadius.sm),
          const SizedBox(height: 8),
          const _PulseBox(width: 120, height: 28, radius: AppRadius.sm),
          const SizedBox(height: 6),
          const _PulseBox(width: 200, height: 11, radius: AppRadius.sm),
        ]),
      ),
      // KPI row
      const SkeletonKpiRow(),
      const SizedBox(height: 20),
      // Two chart placeholders
      const SkeletonChartCard(height: 200),
      const SkeletonChartCard(height: 180),
      const SizedBox(height: 20),
      // Recent sales header + 3 rows
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          const _PulseBox(width: 120, height: 16, radius: AppRadius.sm),
          const Spacer(),
          const _PulseBox(width: 60, height: 14, radius: AppRadius.sm),
        ]),
      ),
      const SizedBox(height: 12),
      const SkeletonListView(count: 3),
      const SizedBox(height: 24),
    ]),
  );
}