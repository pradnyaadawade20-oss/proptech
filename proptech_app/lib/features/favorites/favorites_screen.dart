import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/widgets/property_card.dart';
import '../properties/property_store.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> with PropertyStoreListener<FavoritesScreen> {
  @override
  Widget build(BuildContext context) {
    final favorites = PropertyStore.instance.all.where((p) => p.isFavorite).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: favorites.isEmpty
          ? const Center(child: Text('No favorites yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: favorites.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final property = favorites[index];
                return PropertyCard(
                  property: property,
                  onTap: () => context.push('/property/${property.id}'),
                  onFavoriteTap: () => PropertyStore.instance.toggleFavorite(property.id),
                );
              },
            ),
    );
  }
}