import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/widgets/property_card.dart';
import '../properties/property.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  Widget build(BuildContext context) {
    final favorites = dummyProperties.where((p) => p.isFavorite).toList();

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
                  onFavoriteTap: () {
                    setState(() {
                      final idx = dummyProperties.indexWhere((p) => p.id == property.id);
                      dummyProperties[idx] = property.copyWith(isFavorite: false);
                    });
                  },
                );
              },
            ),
    );
  }
}