import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/components/components.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../platform/modules/module_descriptor.dart';
import '../../platform/modules/module_providers.dart';
import '../../platform/organization/organization_profile.dart';
import '../../platform/data/data_providers.dart';
import '../../platform/organization/institution_seal.dart';
import '../../platform/organization/organization_providers.dart';
import '../../platform/workspace/presentation/institution_switcher.dart';

/// The frame around every screen. Phones get a bottom bar,
/// tablets a navigation rail, desktops a full sidebar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _maxBottomItems = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final modules = ref.watch(visibleModulesProvider);
    final owner = ref.watch(moduleRegistryProvider).forLocation(location);
    final found = owner == null ? -1 : modules.indexWhere((m) => m.id == owner.id);
    final selected = found < 0 ? 0 : found;
    final width = MediaQuery.sizeOf(context).width;
    final topBar = _TopBar(org: ref.watch(activeOrganizationProvider), isDemo: ref.watch(isDemoModeProvider));

    if (width < SdBreakpoints.compact) {
      final overflow = modules.length > _maxBottomItems;
      final primary = overflow ? modules.take(_maxBottomItems - 1).toList() : modules;
      final rest = overflow ? modules.skip(_maxBottomItems - 1).toList() : <ModuleDescriptor>[];
      final barIndex = selected < primary.length ? selected : primary.length;
      return Scaffold(
        appBar: topBar,
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: barIndex,
          onDestinationSelected: (i) {
            if (i < primary.length) {
              context.go(primary[i].route);
            } else {
              _showMore(context, l10n, rest);
            }
          },
          destinations: [
            for (final m in primary)
              NavigationDestination(icon: Icon(m.icon), selectedIcon: Icon(m.selectedIcon), label: m.title(l10n)),
            if (overflow) NavigationDestination(icon: const Icon(Icons.more_horiz), label: l10n.navMore),
          ],
        ),
      );
    }

    final extended = width >= SdBreakpoints.expanded;
    return Scaffold(
      appBar: topBar,
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            minExtendedWidth: 232,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            selectedIndex: selected,
            onDestinationSelected: (i) => context.go(modules[i].route),
            destinations: [
              for (final m in modules)
                NavigationRailDestination(
                  icon: Icon(m.icon),
                  selectedIcon: Icon(m.selectedIcon),
                  label: Text(m.title(l10n)),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  void _showMore(BuildContext context, AppLocalizations l10n, List<ModuleDescriptor> rest) {
    SdSheet.show<void>(
      context,
      title: l10n.moreSheetTitle,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in rest)
            ListTile(
              leading: Icon(m.icon),
              title: Text(m.title(l10n)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.go(m.route);
              },
            ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const _TopBar({required this.org, required this.isDemo});

  final OrganizationProfile org;
  final bool isDemo;

  static const _bannerHeight = 28.0;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (isDemo ? _bannerHeight : 0));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final mediaDir = ref.watch(startupStateProvider).mediaDir;
    return AppBar(
      titleSpacing: SdSpace.sm,
      title: Semantics(
        button: true,
        label: l10n.switcherTitle,
        child: InkWell(
          borderRadius: BorderRadius.circular(SdRadius.sm),
          onTap: () => InstitutionSwitcher.show(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SdSpace.sm, vertical: SdSpace.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InstitutionSeal(
                  initials: org.initials,
                  color: theme.colorScheme.primary,
                  logoFile: InstitutionSeal.logoIn(mediaDir, org.logoFileName),
                ),
                const SizedBox(width: SdSpace.md),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(org.shortName, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                      Text(l10n.academicYear(org.activeAcademicYear), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: SdSpace.xs),
                Icon(Icons.unfold_more, size: 18, color: sd.textMuted),
              ],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: l10n.search,
          icon: const Icon(Icons.search),
          onPressed: () => SdToast.show(context, l10n.searchComingSoon),
        ),
        const SizedBox(width: SdSpace.sm),
      ],
      bottom: isDemo
          ? PreferredSize(
              preferredSize: const Size.fromHeight(_bannerHeight),
              child: Container(
                height: _bannerHeight,
                width: double.infinity,
                color: sd.subtleFill,
                alignment: Alignment.center,
                child: Text(l10n.demoBanner, style: theme.textTheme.labelSmall),
              ),
            )
          : null,
    );
  }
}
