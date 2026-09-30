import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/api/token_store.dart';
import '../../core/widgets/app_button.dart';
import 'property.dart';
import 'property_store.dart';
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
  final _areaController = TextEditingController();
  final _floorController = TextEditingController();
  final _totalFloorsController = TextEditingController();
  final _ageController = TextEditingController();
  final _cityController = TextEditingController();
  final _localityController = TextEditingController();
  final _societyController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _depositController = TextEditingController();
  final _maintenanceController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _category = 'Residential';
  String _bhk = '1 BHK';
  String _furnishing = 'Unfurnished';
  String _priceUnit = '/month';
  final Set<String> _selectedAmenities = {'wifi', 'parking'};

  int _bathrooms = 1;
  int _balconies = 0;
  String _facing = '';
  String _ownership = '';
  String _contactPref = 'both';
  bool _negotiable = false;
  DateTime? _availableFrom;
  final Set<String> _preferredTenants = {};

  final List<String> _facingOptions = ['North', 'South', 'East', 'West', 'North-East', 'North-West', 'South-East', 'South-West'];
  final List<String> _ownershipOptions = ['Freehold', 'Leasehold', 'Co-operative Society', 'Power of Attorney'];
  final List<String> _tenantOptions = ['Family', 'Bachelors', 'Company'];
  final Map<String, String> _contactOptions = const {'call': 'Call', 'chat': 'Chat', 'both': 'Call & Chat'};

  bool get _isRent => _priceUnit == '/month';
  bool get _isPlot => _category == 'Plot/Land';
  bool get _isResidential => _category == 'Residential';

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
    {'key': 'security', 'label': 'Security', 'icon': Icons.security_outlined},
    {'key': 'water_supply', 'label': '24x7 Water', 'icon': Icons.water_drop_outlined},
    {'key': 'gas_pipeline', 'label': 'Gas Pipeline', 'icon': Icons.local_fire_department_outlined},
    {'key': 'cctv', 'label': 'CCTV', 'icon': Icons.videocam_outlined},
    {'key': 'clubhouse', 'label': 'Clubhouse', 'icon': Icons.deck_outlined},
    {'key': 'garden', 'label': 'Garden', 'icon': Icons.park_outlined},
    {'key': 'play_area', 'label': 'Play Area', 'icon': Icons.child_care_outlined},
  ];

  final List<String> _stepTitles = ['Basic Details', 'Location & Price', 'Amenities', 'Photos'];
  /// Photos in display order — the first one is the cover photo.
  final List<XFile> _pickedImages = [];
  XFile? _pickedVideo;
  int _pickedVideoBytes = 0;
  static const int _maxPhotos = 10;
  static const int _maxVideoMb = 50;
  XFile? _pickedFloorPlan;
  final _floorPlanUrlController = TextEditingController();
  @override
  void dispose() {
    _pageController.dispose();
    _titleController.dispose();
    _priceController.dispose();
    _areaController.dispose();
    _floorController.dispose();
    _totalFloorsController.dispose();
    _ageController.dispose();
    _cityController.dispose();
    _localityController.dispose();
    _societyController.dispose();
    _pincodeController.dispose();
    _depositController.dispose();
    _maintenanceController.dispose();
    _descriptionController.dispose();
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
        if (_toDouble(_areaController) <= 0) {
          _showError('Please enter the area in sq ft');
          return false;
        }
        if (!_isPlot) {
          final floor = _toInt(_floorController);
          final total = _toInt(_totalFloorsController);
          if (total > 0 && floor > total) {
            _showError('Floor number cannot be more than total floors');
            return false;
          }
        }
        return true;
      case 1:
        if (_cityController.text.trim().isEmpty) {
          _showError('Please enter the city');
          return false;
        }
        if (_localityController.text.trim().isEmpty) {
          _showError('Please enter the locality / area');
          return false;
        }
        final pin = _pincodeController.text.trim();
        if (pin.isNotEmpty && pin.length != 6) {
          _showError('Pincode must be 6 digits');
          return false;
        }
        if (_toDouble(_priceController) <= 0) {
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

    if (_pickedImages.isEmpty) {
      _showError('Please choose at least one photo from your gallery.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final city = _cityController.text.trim();
      final locality = _localityController.text.trim();
      var created = await PropertyService.instance.create(
        ownerId: ownerId,
        title: _titleController.text.trim(),
        imageUrl: '', // set for real right after upload below
        price: double.tryParse(_priceController.text.trim()) ?? 0,
        priceUnit: _priceUnit,
        bhk: _bhk,
        furnishing: _furnishing,
        // "locality, city" — the app reads the city as the last comma part.
        location: '$locality, $city',
        category: _category,
        amenities: _selectedAmenities.toList(),
        area: _toDouble(_areaController),
        bathrooms: _isResidential ? _bathrooms : 0,
        balconies: _isResidential ? _balconies : 0,
        floorNumber: _isPlot ? 0 : _toInt(_floorController),
        totalFloors: _isPlot ? 0 : _toInt(_totalFloorsController),
        city: city,
        locality: locality,
        society: _societyController.text.trim(),
        pincode: _pincodeController.text.trim(),
        securityDeposit: _isRent ? _toDouble(_depositController) : 0,
        maintenanceCharges: _toDouble(_maintenanceController),
        preferredTenants: _isRent ? _preferredTenants.toList() : const [],
        availableFrom: _availableFrom,
        description: _descriptionController.text.trim(),
        propertyAgeYears: (_isPlot || _ageController.text.trim().isEmpty) ? null : _toInt(_ageController),
        facing: _facing,
        ownershipType: _ownership,
        isPriceNegotiable: _negotiable,
        contactPreference: _contactPref,
      );

      // The first photo is the cover — it shows up everywhere (My
      // Properties, Home, and the buyer's browse/detail screens).
      try {
        final realImageUrl = await PropertyService.instance.uploadImage(created.id, _pickedImages.first);
        created = created.copyWith(imageUrl: realImageUrl);
      } catch (e) {
        if (!mounted) return;
        setState(() => _submitting = false);
        _showError('Could not upload photo: $e');
        return;
      }

      // Remaining photos + the video go into the listing's gallery / video tour.
      final extraImages = _pickedImages.skip(1).toList();
      String? mediaWarning;
      if (extraImages.isNotEmpty || _pickedVideo != null) {
        try {
          final media = await PropertyService.instance.uploadMedia(
            created.id,
            images: extraImages,
            video: _pickedVideo,
          );
          created = created.copyWith(
            additionalImageUrls: media.imageUrls,
            videoTourUrl: media.videoUrl,
          );
        } catch (e) {
          // The listing itself is already created — don't lose it.
          mediaWarning = 'Listed, but some photos/video could not be uploaded: $e';
        }
      }

      PropertyStore.instance.add(created);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mediaWarning ?? 'Property listed successfully!')),
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
        const SizedBox(height: AppSpacing.lg),

        TextFormField(
          controller: _areaController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(
            labelText: _isPlot ? 'Plot Area (sq ft)' : 'Area (sq ft)',
            prefixIcon: const Icon(Icons.square_foot_outlined),
          ),
        ),

        if (_isResidential) ...[
          const SizedBox(height: AppSpacing.lg),
          _counterRow('Bathrooms', _bathrooms, (v) => setState(() => _bathrooms = v), min: 1, max: 10),
          _counterRow('Balconies', _balconies, (v) => setState(() => _balconies = v), min: 0, max: 10),
        ],

        if (!_isPlot) ...[
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _floorController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Floor No.', hintText: '0 = Ground'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  controller: _totalFloorsController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Total Floors'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _ageController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Property Age in years (optional)',
              hintText: '0 = new construction',
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),

        Text('Facing (optional)', style: AppTextStyles.h3.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.sm),
        _singleChoiceChips(_facingOptions, _facing, (v) => setState(() => _facing = v)),
        const SizedBox(height: AppSpacing.lg),

        Text('Ownership (optional)', style: AppTextStyles.h3.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.sm),
        _singleChoiceChips(_ownershipOptions, _ownership, (v) => setState(() => _ownership = v)),
        const SizedBox(height: AppSpacing.lg),

        TextFormField(
          controller: _descriptionController,
          maxLines: 4,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            hintText: 'Tell buyers/tenants what makes this place special',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationPriceStep() {
    return _buildStepCard(
      heading: 'Where is it & what\'s the price?',
      children: [
        TextFormField(
          controller: _cityController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'City',
            hintText: 'e.g. Mumbai',
            prefixIcon: Icon(Icons.location_city_outlined),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _localityController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Locality / Area',
            hintText: 'e.g. Powai',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _societyController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Society / Building name (optional)',
            prefixIcon: Icon(Icons.apartment_outlined),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _pincodeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Pincode (optional)',
            counterText: '',
            prefixIcon: Icon(Icons.pin_drop_outlined),
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

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Price is negotiable'),
          value: _negotiable,
          activeThumbColor: AppColors.primary,
          onChanged: (v) => setState(() => _negotiable = v),
        ),
        const SizedBox(height: AppSpacing.sm),

        if (_isRent) ...[
          TextFormField(
            controller: _depositController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Security Deposit (₹)',
              prefixIcon: Icon(Icons.currency_rupee),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        TextFormField(
          controller: _maintenanceController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: _isRent ? 'Maintenance (₹/month, if extra)' : 'Maintenance (₹/month, optional)',
            prefixIcon: const Icon(Icons.currency_rupee),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        if (_isRent) ...[
          Text('Preferred Tenants', style: AppTextStyles.h3.copyWith(fontSize: 15)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: _tenantOptions.map((option) {
              final isSelected = _preferredTenants.contains(option);
              return FilterChip(
                label: Text(option),
                selected: isSelected,
                onSelected: (v) => setState(() {
                  if (v) {
                    _preferredTenants.add(option);
                  } else {
                    _preferredTenants.remove(option);
                  }
                }),
                selectedColor: AppColors.primary,
                checkmarkColor: Colors.white,
                labelStyle: AppTextStyles.bodySmall.copyWith(
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        Text(_isRent ? 'Available From' : 'Available / Possession From',
            style: AppTextStyles.h3.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickAvailableFrom,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(_availableFrom == null ? 'Select date' : _formatDate(_availableFrom!)),
              ),
            ),
            if (_availableFrom != null)
              IconButton(
                onPressed: () => setState(() => _availableFrom = null),
                icon: const Icon(Icons.close, color: AppColors.error),
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
        const SizedBox(height: AppSpacing.xl),

        Text('How should buyers/tenants contact you?', style: AppTextStyles.h3.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _contactOptions.entries.map((e) {
            final isSelected = _contactPref == e.key;
            return ChoiceChip(
              label: Text(e.value),
              selected: isSelected,
              onSelected: (_) => setState(() => _contactPref = e.key),
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
        Row(
          children: [
            Text('Photos', style: AppTextStyles.h3.copyWith(fontSize: 15)),
            const Spacer(),
            Text('${_pickedImages.length}/$_maxPhotos', style: AppTextStyles.bodySmall),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _pickedImages.isNotEmpty
                ? _photoThumb(_pickedImages.first)
                : Container(
                    color: AppColors.surfaceSoft,
                    child: const Center(
                      child: Icon(Icons.image_outlined, size: 40, color: AppColors.textHint),
                    ),
                  ),
          ),
        ),
        if (_pickedImages.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _pickedImages.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) => _buildPhotoTile(i),
            ),
          ),
        ] else if (_pickedImages.length == 1) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(height: 72, child: Align(alignment: Alignment.centerLeft, child: _buildPhotoTile(0))),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          _pickedImages.isEmpty
              ? 'Select one or more photos. The first one becomes the cover.'
              : 'First photo is the cover. Tap a photo to make it the cover.',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),

        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickedImages.length >= _maxPhotos ? null : _pickFromGallery,
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: Text(_pickedImages.isEmpty ? 'Choose from Gallery' : 'Add more photos'),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Video tour — optional, shown as "Video Tour" on the detail screen.
        Text('Video Tour (optional)', style: AppTextStyles.h3.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'A short walkthrough video (up to $_maxVideoMb MB) helps buyers/tenants trust your listing.',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_pickedVideo != null)
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(Icons.videocam_outlined, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_pickedVideo!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${(_pickedVideoBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                          style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _pickedVideo = null;
                    _pickedVideoBytes = 0;
                  }),
                  icon: const Icon(Icons.close, color: AppColors.error),
                ),
              ],
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.video_library_outlined, size: 18),
              label: const Text('Add Video'),
            ),
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

  Widget _photoThumb(XFile file) => kIsWeb
      ? Image.network(file.path, fit: BoxFit.cover)
      : Image.file(File(file.path), fit: BoxFit.cover);

  Widget _buildPhotoTile(int i) {
    final isCover = i == 0;
    return GestureDetector(
      onTap: isCover
          ? null
          : () => setState(() {
                final f = _pickedImages.removeAt(i);
                _pickedImages.insert(0, f);
              }),
      child: SizedBox(
        width: 72,
        height: 72,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: _photoThumb(_pickedImages[i]),
            ),
            if (isCover)
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Cover', style: TextStyle(color: Colors.white, fontSize: 10)),
                ),
              ),
            Positioned(
              right: 2,
              top: 2,
              child: GestureDetector(
                onTap: () => setState(() => _pickedImages.removeAt(i)),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 80);
    if (images.isEmpty) return;
    final room = _maxPhotos - _pickedImages.length;
    setState(() => _pickedImages.addAll(images.take(room)));
    if (images.length > room) {
      _showError('You can add up to $_maxPhotos photos — extra ones were skipped.');
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 3),
    );
    if (video == null) return;
    final bytes = await video.length();
    if (bytes > _maxVideoMb * 1024 * 1024) {
      _showError('Video is too large. Please pick one under $_maxVideoMb MB.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _pickedVideo = video;
      _pickedVideoBytes = bytes;
    });
  }


  int _toInt(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
  double _toDouble(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickAvailableFrom() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _availableFrom ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3, now.month, now.day),
    );
    if (picked != null) setState(() => _availableFrom = picked);
  }

  /// Single-select chips; tapping the selected chip again clears it.
  Widget _singleChoiceChips(List<String> options, String selected, ValueChanged<String> onChanged) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: options.map((option) {
        final isSelected = selected == option;
        return ChoiceChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (_) => onChanged(isSelected ? '' : option),
          selectedColor: AppColors.primary,
          labelStyle: AppTextStyles.bodySmall.copyWith(
            color: isSelected ? Colors.white : AppColors.textPrimary,
          ),
        );
      }).toList(),
    );
  }

  Widget _counterRow(String label, int value, ValueChanged<int> onChanged, {int min = 0, int max = 10}) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTextStyles.h3.copyWith(fontSize: 15))),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center, style: AppTextStyles.bodySmall)),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}