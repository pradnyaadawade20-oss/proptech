/// Content for a single onboarding slide.
class OnboardingSlideData {
  final String title;
  final String description;
  final String imagePath;

  const OnboardingSlideData({
    required this.title,
    required this.description,
    required this.imagePath,
  });
}

final List<OnboardingSlideData> onboardingSlides = [
  const OnboardingSlideData(
    title: 'Search with smart filters',
    description: 'Find verified 1BHK, 2BHK, PG and more by location, price and furnishing.',
    imagePath: 'assets/images/onboarding_1.jpg',
  ),
  const OnboardingSlideData(
    title: 'Chat & schedule visits',
    description: 'Message owners directly and book property visits in a few taps.',
    imagePath: 'assets/images/onboarding_2.jpg',
  ),
  const OnboardingSlideData(
    title: 'List & manage as an owner',
    description: 'Post your property, track leads, visits and chats from one dashboard.',
    imagePath: 'assets/images/onboarding_3.jpg',
  ),
];