import 'package:flutter/material.dart';
import '../../models/activity_log_model.dart';
import '../../services/activity_log_service.dart';
import '../../services/report_export_service.dart';
import '../../theme/app_theme.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});
  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final ActivityLogService     _logs      = ActivityLogService();
  final ReportExportService    _exportSvc = ReportExportService();
  final TextEditingController  _searchCtrl = TextEditingController();

  String          _searchQuery  = '';
  ActivityEntity? _entityFilter;
  bool            _exporting    = false;

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final logs = await _logs.fetchLogsInRange(
        DateTime.now().subtract(const Duration(days: 90)),
        DateTime.now(),
      );
      final path = await _exportSvc.exportActivityLogCsv(logs);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.textPrimary, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Saved: ${path.split('/').last}',
                style: AppText.body().copyWith(fontSize: 13))),
          ]),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e', style: AppText.body()),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<ActivityLogModel> _filter(List<ActivityLogModel> logs) {
    return logs.where((l) {
      final matchSearch = _searchQuery.isEmpty ||
          l.username.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          l.action.value.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchEntity = _entityFilter == null || l.entity == _entityFilter;
      return matchSearch && matchEntity;
    }).toList();
  }

  _ActionMeta _metaFor(ActivityAction a) {
    switch (a) {
      case ActivityAction.login:         return const _ActionMeta(Icons.login_rounded, AppColors.success);
      case ActivityAction.logout:        return const _ActionMeta(Icons.logout_rounded, AppColors.primary);
      case ActivityAction.productCreate: return const _ActionMeta(Icons.add_box_rounded, AppColors.success);
      case ActivityAction.productUpdate: return const _ActionMeta(Icons.edit_rounded, AppColors.teal);
      case ActivityAction.productDelete: return const _ActionMeta(Icons.delete_rounded, AppColors.danger);
      case ActivityAction.salesCreate:   return const _ActionMeta(Icons.receipt_long_rounded, AppColors.primary);
      case ActivityAction.salesUpdate:   return const _ActionMeta(Icons.edit_note_rounded, AppColors.warning);
      case ActivityAction.salesComplete: return const _ActionMeta(Icons.check_circle_rounded, AppColors.success);
      case ActivityAction.salesCancel:   return const _ActionMeta(Icons.cancel_rounded, AppColors.danger);
      case ActivityAction.userCreate:    return const _ActionMeta(Icons.person_add_rounded, AppColors.success);
      case ActivityAction.userUpdate:    return const _ActionMeta(Icons.manage_accounts_rounded, AppColors.teal);
      case ActivityAction.userDelete:    return const _ActionMeta(Icons.person_remove_rounded, AppColors.danger);
      case ActivityAction.roleChange:    return const _ActionMeta(Icons.shield_rounded, AppColors.magenta);
      case ActivityAction.paymentRecord: return const _ActionMeta(Icons.payments_rounded, AppColors.success);
      case ActivityAction.paymentRefund: return const _ActionMeta(Icons.undo_rounded, AppColors.warning);
    }
  }

  IconData _entityIcon(ActivityEntity e) {
    switch (e) {
      case ActivityEntity.auth:    return Icons.lock_outline_rounded;
      case ActivityEntity.product: return Icons.inventory_2_outlined;
      case ActivityEntity.sale:    return Icons.receipt_outlined;
      case ActivityEntity.user:    return Icons.people_outline_rounded;
      case ActivityEntity.payment: return Icons.account_balance_wallet_outlined;
    }
  }

  void _showDetail(ActivityLogModel log) {
    final meta = _metaFor(log.action);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.textFaint, borderRadius: AppRadius.handleRadius)),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: meta.color.withValues(alpha: .15), borderRadius: AppRadius.lgRadius),
                child: Icon(meta.icon, color: meta.color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(log.action.value, style: AppText.title().copyWith(fontSize: 17)),
                Text(log.entity.value, style: AppText.caption(color: AppColors.textDisabled)),
              ])),
            ]),
            const SizedBox(height: 20),
            _detailRow('Performed By', log.username),
            _detailRow('User ID', log.userId),
            _detailRow('Record ID', log.recordId),
            _detailRow('Timestamp', _fullDate(log.timestamp)),
            if (log.details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: Text('Additional Details',
                  style: AppText.caption(color: AppColors.textDisabled).copyWith(fontWeight: FontWeight.w500))),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: AppRadius.lgRadius),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: log.details.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Text('${_humanize(e.key)}: ', style: AppText.body(color: AppColors.textSecondary).copyWith(fontSize: 13)),
                      Expanded(child: Text('${e.value}', style: AppText.body().copyWith(fontSize: 13, fontWeight: FontWeight.w500))),
                    ]),
                  )).toList(),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      SizedBox(width: 110, child: Text(label, style: AppText.body(color: AppColors.textDisabled).copyWith(fontSize: 13))),
      Expanded(child: Text(value, style: AppText.body().copyWith(fontSize: 13, fontWeight: FontWeight.w500))),
    ]),
  );

  String _humanize(String camel) {
    final s = camel.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}');
    return s[0].toUpperCase() + s.substring(1);
  }

  String _fullDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}  '
      '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}:${d.second.toString().padLeft(2,'0')}';

  String _relativeTime(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            expandedHeight: 130,
            pinned: true, floating: false,
            backgroundColor: AppColors.background,
            elevation: 0,
            automaticallyImplyLeading: false,
            actions: [
              _exporting
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
                    )
                  : IconButton(
                      icon: const Icon(Icons.download_rounded, color: AppColors.textPrimary),
                      tooltip: 'Export as CSV',
                      onPressed: _exportCsv,
                    ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Activity Log', style: AppText.headline()),
                    Text('Full system audit trail', style: AppText.body(color: AppColors.textTertiary).copyWith(fontSize: 13)),
                  ]),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(gradient: AppGradients.primary, borderRadius: AppRadius.mdRadius),
                    child: const Icon(Icons.history_rounded, color: AppColors.textPrimary, size: 20),
                  ),
                ]),
              )),
            ),
          ),
        ],
        body: Column(children: [
          Container(
            color: AppColors.background,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.lgRadius,
                  border: Border.all(color: AppColors.border)),
                child: TextField(
                  controller: _searchCtrl,
                  style: AppText.body(),
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search by user or action...',
                    hintStyle: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textDisabled),
                    suffixIcon: _searchQuery.isNotEmpty ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: AppColors.textDisabled, size: 18),
                        onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); }) : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(height: 36, child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _entityChip(null, 'All', Icons.list_rounded),
                  _entityChip(ActivityEntity.auth, 'Auth', _entityIcon(ActivityEntity.auth)),
                  _entityChip(ActivityEntity.product, 'Product', _entityIcon(ActivityEntity.product)),
                  _entityChip(ActivityEntity.sale, 'Sale', _entityIcon(ActivityEntity.sale)),
                  _entityChip(ActivityEntity.user, 'User', _entityIcon(ActivityEntity.user)),
                  _entityChip(ActivityEntity.payment, 'Payment', _entityIcon(ActivityEntity.payment)),
                ],
              )),
            ]),
          ),
          Expanded(child: StreamBuilder<List<ActivityLogModel>>(
            stream: _logs.getRecentLogs(limit: 200),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primary));
              }
              if (!snap.hasData || snap.data!.isEmpty) return _emptyState();
              final filtered = _filter(snap.data!);
              if (filtered.isEmpty) return _noResults();
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) => _logCard(filtered[i]),
              );
            },
          )),
        ]),
      ),
    );
  }

  Widget _entityChip(ActivityEntity? entity, String label, IconData icon) {
    final isSelected = _entityFilter == entity;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _entityFilter = entity),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: .2) : AppColors.surface,
            borderRadius: AppRadius.xlRadius,
            border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: isSelected ? AppColors.primary : AppColors.textDisabled),
            const SizedBox(width: 5),
            Text(label, style: AppText.caption(
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
              ).copyWith(fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
          ]),
        ),
      ),
    );
  }

  Widget _logCard(ActivityLogModel log) {
    final meta = _metaFor(log.action);
    return GestureDetector(
      onTap: () => _showDetail(log),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .06)),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [meta.color.withValues(alpha: .3), meta.color.withValues(alpha: .1)]),
              borderRadius: AppRadius.mdRadius),
            child: Icon(meta.icon, color: meta.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(log.action.value, style: AppText.body().copyWith(fontSize: 14, fontWeight: FontWeight.w600))),
              Text(_relativeTime(log.timestamp), style: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 11)),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              const Icon(Icons.person_outline_rounded, color: AppColors.textDisabled, size: 12),
              const SizedBox(width: 4),
              Expanded(child: Text(log.username, style: AppText.caption(color: AppColors.textTertiary), overflow: TextOverflow.ellipsis)),
            ]),
          ])),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint, size: 18),
        ]),
      ),
    );
  }

  Widget _emptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
        child: const Icon(Icons.history_rounded, color: AppColors.primary, size: 48)),
    const SizedBox(height: 16),
    Text('No Activity Yet', style: AppText.title().copyWith(fontSize: 18)),
    const SizedBox(height: 8),
    Text('System actions will appear here', style: AppText.body(color: AppColors.textDisabled)),
  ]));

  Widget _noResults() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.search_off_rounded, color: AppColors.primary, size: 56),
    const SizedBox(height: 16),
    Text('No Results Found', style: AppText.title().copyWith(fontSize: 18)),
    const SizedBox(height: 8),
    TextButton(
      onPressed: () { _searchCtrl.clear(); setState(() { _searchQuery = ''; _entityFilter = null; }); },
      child: Text('Clear Filters', style: AppText.buttonLabel(color: AppColors.primary).copyWith(fontSize: 14)),
    ),
  ]));
}

class _ActionMeta {
  final IconData icon;
  final Color    color;
  const _ActionMeta(this.icon, this.color);
}