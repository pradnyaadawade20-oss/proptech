import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/api/token_store.dart';
import '../../core/widgets/app_button.dart';
import 'property.dart';
import 'property_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AddPropertyScreen extends StatefulWidget {
  const AddPropertyScreen({super.key});

  @override
  State<AddPropertyScreen> createState() => _AddPropertyScreenState();
}

class _AddPropertyScreenState extends State<AddPropertyScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 4;

  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();
  final _imageUrlController = TextEditingController();

  String _category = 'Residential';
  String _bhk = '1 BHK';
  String _furnishing = 'Unfurnished';
  String _priceUnit = '/month';
  final Set<String> _selectedAmenities = {'wifi', 'parking'};

  final List<String> _categoryOptions = ['Residential', 'Commercial', 'Plot/Land'];
  final List<String> _bhkOptions = ['1 BHK', '2 BHK', '3 BHK', 'PG'];
  final List<String> _commercialTypeOptions = ['Office Space', 'Shop', 'Warehouse', 'Showroom'];
  final List<String> _plotTypeOptions = ['Residential Plot', 'NA Plot', 'Agricultural Land', 'Farm House Land'];
  final List<String> _furnishingOptions = ['Unfurnished', 'Semi Furnished', 'Fully Furnished'];
  final List<Map<String, dynamic>> _amenityOptions = const [
    {'key': 'wifi', 'label': 'Wifi', 'icon': Icons.wifi},
    {'key': 'parking', 'label': 'Parking', 'icon': Icons.local_parking_outlined},
    {'key': 'lift', 'label': 'Lift', 'icon': Icons.elevator_outlined},
    {'key': 'power_backup', 'label': 'Power Backup', 'icon': Icons.power_outlined},
    {'key': 'gym', 'label': 'Gym', 'icon': Icons.fitness_center_outlined},
    {'key': 'pool', 'label': 'Pool', 'icon': Icons.pool_outlined},
  ];

  final List<String> _stepTitles = ['Basic Details', 'Location & Price', 'Amenities', 'Photos'];
  XFile? _pickedImage;
  XFile? _pickedFloorPlan;
  final _floorPlanUrlController = TextEditingController();
  @override
  void dispose() {
    _pageController.dispose();
    _titleController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    _imageUrlController.dispose();
    _floorPlanUrlController.dispose();
    super.dispose();
  }

  bool get _isLastStep => _currentStep == _totalSteps - 1;

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (_titleController.text.trim().isEmpty) {
          _showError('Please enter a property title');
          return false;
        }
        return true;
      case 1:
        if (_locationController.text.trim().isEmpty) {
          _showError('Please enter the location');
          return false;
        }
        if (_priceController.text.trim().isEmpty) {
          _showError('Please enter the price');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _next() {
    if (!_validateCurrentStep()) return;

    if (_isLastStep) {
      _submit();
    } else {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _back() {
    if (_currentStep == 0) {
      context.pop();
    } else {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  bool _submitting = false;

  Future<void> _submit() async {
    final ownerId = await TokenStore.instance.getUserId();
    if (!mounted) return;
    if (ownerId == null) {
      _showError('Please log in to list a property.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final created = await PropertyService.instance.create(
        ownerId: ownerId,
        title: _titleController.text.trim(),
        imageUrl: _imageUrlController.text.trim().isEmpty
            ? 'https://images.unsplash.com/photo-1568605114967-8130f3a36994'
            : _imageUrlController.text.trim(),
        price: double.tryParse(_priceController.text.trim()) ?? 0,
        priceUnit: _priceUnit,
        bhk: _bhk,
        furnishing: _furnishing,
        location: _locationController.text.trim(),
        category: _category,
        amenities: _selectedAmenities.toList(),
      );

      // Also drop it into dummyProperties so it shows up immediately in
      // screens (Home, My Properties) that haven't been switched over to
      // fetch from the API yet.
      dummyProperties.add(created);
      notifyPropertiesChanged();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Property listed successfully!')),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showError('Could not list property: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
        ),
        title: Text(_stepTitles[_currentStep]),
      ),
      body: Column(
        children: [
          // Progress indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: List.generate(_totalSteps, (index) {
                    final isActive = index <= _currentStep;
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: index == _totalSteps - 1 ? 0 : 6),
                        height: 4,
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.primary : AppColors.surfaceSoft,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  'Step ${_currentStep + 1} of $_totalSteps',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

          // Step content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildBasicDetailsStep(),
                _buildLocationPriceStep(),
                _buildAmenitiesStep(),
                _buildPhotosStep(),
              ],
            ),
          ),

          // Bottom button
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: AppButton(
              label: _isLastStep ? 'List Property' : 'Next',
              onPressed: _next,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard({required String heading, required List<Widget> children}) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(heading, style: AppTextStyles.h2),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'This helps buyers/tenants find your property easily.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ],
    );
  }

  Widget _buildBasicDetailsStep() {
    return _buildStepCard(
      heading: 'Tell us about your property',
      children: [
        TextFormField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Property Title',
            hintText: 'e.g. Spacious 2 BHK near metro',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        Text('Category', style: AppTextStyles.h3.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _categoryOptions.map((option) {
            final isSelected = _category == option;
            return ChoiceChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (_) => setState(() {
                _category = option;
                // Reset type default when switching category
                if (option == 'Commercial') {
                  _bhk = _commercialTypeOptions.first;
                } else if (option == 'Plot/Land') {
                  _bhk = _plotTypeOptions.first;
                } else {
                  _bhk = _bhkOptions.first;
                }
              }),
              selectedColor: AppColors.primary,
              labelStyle: AppTextStyles.bodySmall.copyWith(
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.lg),

        Text('Property Type', style: AppTextStyles.h3.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: (_category == 'Commercial'
                  ? _commercialTypeOptions
                  : _category == 'Plot/Land'
                      ? _plotTypeOptions
                      : _bhkOptions)
              .map((option) {
            final isSelected = _bhk == option;
            return ChoiceChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (_) => setState(() => _bhk = option),
              selectedColor: AppColors.primary,
              labelStyle: AppTextStyles.bodySmall.copyWith(
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            );
          }).toList(),
        ),
        if (_category == 'Commercial') ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Tip: mention carpet area in sq.ft in the title (e.g. "1200 sq.ft Office Space")',
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
        if (_category == 'Plot/Land') ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Tip: mention plot area in sq.ft in the title (e.g. "1200 sq.ft NA Plot")',
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _buildLocationPriceStep() {
    return _buildStepCard(
      heading: 'Where is it & what\'s the price?',
      children: [
        TextFormField(
          controller: _locationController,
          decoration: const InputDecoration(
            labelText: 'Location',
            hintText: 'e.g. Powai, Mumbai',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Price (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _priceUnit,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: '/month', child: Text('Rent')),
                  DropdownMenuItem(value: '', child: Text('Sale')),
                ],
                onChanged: (value) => setState(() => _priceUnit = value!),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        Text('Furnishing', style: AppTextStyles.h3.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _furnishingOptions.map((option) {
            final isSelected = _furnishing == option;
            return ChoiceChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (_) => setState(() => _furnishing = option),
              selectedColor: AppColors.primary,
              labelStyle: AppTextStyles.bodySmall.copyWith(
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAmenitiesStep() {
    return _buildStepCard(
      heading: 'What amenities are available?',
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _amenityOptions.map((amenity) {
            final key = amenity['key'] as String;
            final isSelected = _selectedAmenities.contains(key);
            return FilterChip(
              label: Text(amenity['label'] as String),
              avatar: Icon(
                amenity['icon'] as IconData,
                size: 16,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedAmenities.add(key);
                  } else {
                    _selectedAmenities.remove(key);
                  }
                });
              },
              selectedColor: AppColors.primary,
              labelStyle: AppTextStyles.bodySmall.copyWith(
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPhotosStep() {
    return _buildStepCard(
      heading: 'Add photos',
      children: [
        Text('Preview', style: AppTextStyles.h3.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _pickedImage != null
                ? (kIsWeb
                    ? Image.network(_pickedImage!.path, fit: BoxFit.cover)
                    : Image.file(File(_pickedImage!.path), fit: BoxFit.cover))
                : _imageUrlController.text.trim().isEmpty
                    ? Container(
                        color: AppColors.surfaceSoft,
                        child: const Center(
                          child: Icon(Icons.image_outlined, size: 40, color: AppColors.textHint),
                        ),
                      )
                    : Image.network(
                        _imageUrlController.text.trim(),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: AppColors.surfaceSoft,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined, size: 40, color: AppColors.textHint),
                          ),
                        ),
                      ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickFromGallery,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Choose from Gallery'),
              ),
            ),
            if (_pickedImage != null) ...[
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                onPressed: () => setState(() => _pickedImage = null),
                icon: const Icon(Icons.close, color: AppColors.error),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text('OR', style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
            ),
            const Expanded(child: Divider(color: AppColors.border)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        TextFormField(
          controller: _imageUrlController,
          decoration: const InputDecoration(
            labelText: 'Image URL (optional)',
            hintText: 'Paste an image link',
            prefixIcon: Icon(Icons.link),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Floor plan — optional, shown as its own section on the detail
        // screen once uploaded (same pick-from-gallery / paste-URL pattern
        // as the cover photo above).
        Text('Floor Plan (optional)', style: AppTextStyles.h3.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Helps buyers/tenants understand the layout at a glance.',
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _pickedFloorPlan != null
                ? (kIsWeb
                    ? Image.network(_pickedFloorPlan!.path, fit: BoxFit.cover)
                    : Image.file(File(_pickedFloorPlan!.path), fit: BoxFit.cover))
                : _floorPlanUrlController.text.trim().isEmpty
                    ? Container(
                        color: AppColors.surfaceSoft,
                        child: const Center(
                          child: Icon(Icons.architecture_outlined, size: 40, color: AppColors.textHint),
                        ),
                      )
                    : Image.network(
                        _floorPlanUrlController.text.trim(),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: AppColors.surfaceSoft,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined, size: 40, color: AppColors.textHint),
                          ),
                        ),
                      ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickFloorPlanFromGallery,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Upload Floor Plan'),
              ),
            ),
            if (_pickedFloorPlan != null) ...[
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                onPressed: () => setState(() => _pickedFloorPlan = null),
                icon: const Icon(Icons.close, color: AppColors.error),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text('OR', style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
            ),
            const Expanded(child: Divider(color: AppColors.border)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        TextFormField(
          controller: _floorPlanUrlController,
          decoration: const InputDecoration(
            labelText: 'Floor Plan URL (optional)',
            hintText: 'Paste a floor plan image link',
            prefixIcon: Icon(Icons.link),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Future<void> _pickFloorPlanFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      setState(() {
        _pickedFloorPlan = image;
        _floorPlanUrlController.clear();
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      setState(() {
        _pickedImage = image;
        _imageUrlController.clear();
      });
    }
  }
}