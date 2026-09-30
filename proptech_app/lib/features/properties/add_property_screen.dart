import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/api/token_store.dart';
import '../../core/widgets/app_button.dart';
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
  final _locationController = TextEditingController();

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
    _locationController.dispose();
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

    if (_pickedImages.isEmpty) {
      _showError('Please choose at least one photo from your gallery.');
      return;
    }

    setState(() => _submitting = true);
    try {
      var created = await PropertyService.instance.create(
        ownerId: ownerId,
        title: _titleController.text.trim(),
        imageUrl: '', // set for real right after upload below
        price: double.tryParse(_priceController.text.trim()) ?? 0,
        priceUnit: _priceUnit,
        bhk: _bhk,
        furnishing: _furnishing,
        location: _locationController.text.trim(),
        category: _category,
        amenities: _selectedAmenities.toList(),
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
}