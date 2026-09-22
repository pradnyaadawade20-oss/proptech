import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/property_card.dart';
import '../properties/property.dart';
import 'saved_search.dart';
import 'saved_search_store.dart';

/// Shows the properties currently matching one saved search, and marks
/// them all as "seen" so the new-match badge clears once the user has
/// actually looked at the results.
class SavedSearchResultsScreen extends StatefulWidget {
  final SavedSearch search;
  const SavedSearchResultsScreen({super.key, required this.search});

  @override
  State<SavedSearchResultsScreen> createState() => _SavedSearchResultsScreenState();
}

class _SavedSearchResultsScreenState extends State<SavedSearchResultsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SavedSearchStore.instance.markSeen(widget.search);
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = SavedSearchStore.instance.matchingProperties(widget.search);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.search.name),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.search.summary,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                      'No properties match this search right now',
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final property = results[index];
                      return PropertyCard(
                        property: property,
                        onTap: () => context.push('/property/${property.id}'),
                        onFavoriteTap: () {
                          final i = dummyProperties.indexWhere((p) => p.id == property.id);
                          if (i != -1) {
                            dummyProperties[i] = property.copyWith(isFavorite: !property.isFavorite);
                            notifyPropertiesChanged();
                            setState(() {});
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}