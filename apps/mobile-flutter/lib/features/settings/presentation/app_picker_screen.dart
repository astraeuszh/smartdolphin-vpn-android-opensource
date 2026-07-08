import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/apps/installed_apps_provider.dart';
import '../../../services/apps/installed_apps_service.dart';
import '../domain/settings_controller.dart';

/// Pick installed apps for per-app split tunnel (include / exclude).
class AppPickerScreen extends ConsumerStatefulWidget {
  const AppPickerScreen({super.key});

  @override
  ConsumerState<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends ConsumerState<AppPickerScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected =
        ref.watch(settingsControllerProvider).splitTunnel.selectedPackages;
    final appsAsync = ref.watch(installedAppsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsAppSelectApps),
        actions: [
          TextButton(
            onPressed: selected.isEmpty
                ? null
                : () async {
                    await ref
                        .read(settingsControllerProvider.notifier)
                        .setSelectedPackages({});
                  },
            child: Text(l10n.settingsAppPickerClear),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.settingsAppPickerSearch,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.settingsAppSplitAppCount(selected.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: appsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('${l10n.settingsAppPickerLoadFailed}\n$e'),
                ),
              ),
              data: (apps) {
                final filtered = _filterApps(apps);
                if (filtered.isEmpty) {
                  return Center(child: Text(l10n.settingsAppPickerEmpty));
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final app = filtered[index];
                    final checked = selected.contains(app.packageName);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (_) => _toggle(app.packageName),
                      title: Text(app.appName),
                      subtitle: Text(
                        app.packageName,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      secondary: CircleAvatar(
                        child: Text(
                          app.appName.isNotEmpty
                              ? app.appName[0].toUpperCase()
                              : '?',
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<InstalledAppInfo> _filterApps(List<InstalledAppInfo> apps) {
    if (_query.isEmpty) return apps;
    return apps
        .where(
          (a) =>
              a.appName.toLowerCase().contains(_query) ||
              a.packageName.toLowerCase().contains(_query),
        )
        .toList();
  }

  Future<void> _toggle(String packageName) async {
    final current =
        ref.read(settingsControllerProvider).splitTunnel.selectedPackages;
    final next = Set<String>.from(current);
    if (next.contains(packageName)) {
      next.remove(packageName);
    } else {
      next.add(packageName);
    }
    await ref.read(settingsControllerProvider.notifier).setSelectedPackages(next);
  }
}
