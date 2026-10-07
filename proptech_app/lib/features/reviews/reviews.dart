class Review {
  final String id;
  final String userId;
  final String userName;
  final String userAvatarUrl;
  final int rating; // 1-5
  final String comment;
  final DateTime createdAt;

  const Review({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatarUrl = '',
    required this.rating,
    this.comment = '',
    required this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      userName: json['user_name'] as String? ?? '',
      userAvatarUrl: json['user_avatar_url'] as String? ?? '',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}

/// Result of GET /api/properties/:id/reviews/eligibility.
class ReviewEligibility {
  final bool canReview;

  /// 'already_reviewed' | 'no_completed_visit' | '' (when [canReview]).
  final String reason;
  const ReviewEligibility({required this.canReview, this.reason = ''});
}