enum AgreementStatus {
  requested,
  draftReady,
  awaitingSignatures,
  signedByOwner,
  signedByTenant,
  completed,
  rejected,
  cancelled,
  expired,
}

extension AgreementStatusX on AgreementStatus {
  String get apiValue => switch (this) {
        AgreementStatus.requested => 'requested',
        AgreementStatus.draftReady => 'draft_ready',
        AgreementStatus.awaitingSignatures => 'awaiting_signatures',
        AgreementStatus.signedByOwner => 'signed_by_owner',
        AgreementStatus.signedByTenant => 'signed_by_tenant',
        AgreementStatus.completed => 'completed',
        AgreementStatus.rejected => 'rejected',
        AgreementStatus.cancelled => 'cancelled',
        AgreementStatus.expired => 'expired',
      };

  String get label => switch (this) {
        AgreementStatus.requested => 'Requested',
        AgreementStatus.draftReady => 'Draft ready',
        AgreementStatus.awaitingSignatures => 'Awaiting signatures',
        AgreementStatus.signedByOwner => 'Signed by owner',
        AgreementStatus.signedByTenant => 'Signed by tenant',
        AgreementStatus.completed => 'Completed',
        AgreementStatus.rejected => 'Rejected',
        AgreementStatus.cancelled => 'Cancelled',
        AgreementStatus.expired => 'Expired',
      };

  /// User-facing state from spec 12.5: Pending -> Approved / Rejected ->
  /// Signed -> Expired / Cancelled. ("Approved" = owner accepted and the draft
  /// is ready; a one-sided signature shows as "Partially signed".)
  String get displayLabel => switch (this) {
        AgreementStatus.requested => 'Pending',
        AgreementStatus.draftReady => 'Approved',
        AgreementStatus.awaitingSignatures => 'Approved',
        AgreementStatus.signedByOwner => 'Partially signed',
        AgreementStatus.signedByTenant => 'Partially signed',
        AgreementStatus.completed => 'Signed',
        AgreementStatus.rejected => 'Rejected',
        AgreementStatus.cancelled => 'Cancelled',
        AgreementStatus.expired => 'Expired',
      };

  /// No further action is possible (signed, or closed without signing).
  bool get isFinal =>
      this == AgreementStatus.completed || isClosedWithoutSigning;

  /// Rejected / cancelled / expired.
  bool get isClosedWithoutSigning =>
      this == AgreementStatus.rejected ||
      this == AgreementStatus.cancelled ||
      this == AgreementStatus.expired;

  static AgreementStatus fromApi(String value) => switch (value) {
        'draft_ready' => AgreementStatus.draftReady,
        'awaiting_signatures' => AgreementStatus.awaitingSignatures,
        'signed_by_owner' => AgreementStatus.signedByOwner,
        'signed_by_tenant' => AgreementStatus.signedByTenant,
        'completed' => AgreementStatus.completed,
        'rejected' => AgreementStatus.rejected,
        'cancelled' => AgreementStatus.cancelled,
        'expired' => AgreementStatus.expired,
        _ => AgreementStatus.requested,
      };
}

/// How a party signed — drawn on canvas, or typed name rendered as a signature.
enum SignatureType { draw, type }

extension SignatureTypeX on SignatureType {
  String get apiValue => this == SignatureType.draw ? 'draw' : 'type';
}

class Agreement {
  final String id;
  final String propertyId;
  final String propertyTitle;
  final String propertyImageUrl;
  final String ownerId;
  final String ownerName;
  final String tenantId;
  final String tenantName;
  final AgreementStatus status;

  final double? monthlyRent;
  final double? securityDeposit;
  final DateTime? startDate;
  final int? durationMonths;
  final String? terms;

  final SignatureType? ownerSignatureType;
  final String? ownerSignatureData; // base64 PNG or typed name
  final DateTime? ownerSignedAt;

  final SignatureType? tenantSignatureType;
  final String? tenantSignatureData;
  final DateTime? tenantSignedAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Deadline for the next step (null once the agreement is final).
  final DateTime? expiresAt;

  /// Why / who / when for rejected, cancelled and expired. [statusChangedBy] is
  /// null when the system expired the agreement.
  final String? statusReason;
  final String? statusChangedBy;
  final DateTime? statusChangedAt;

  const Agreement({
    required this.id,
    required this.propertyId,
    required this.propertyTitle,
    required this.propertyImageUrl,
    required this.ownerId,
    required this.ownerName,
    required this.tenantId,
    required this.tenantName,
    required this.status,
    this.monthlyRent,
    this.securityDeposit,
    this.startDate,
    this.durationMonths,
    this.terms,
    this.ownerSignatureType,
    this.ownerSignatureData,
    this.ownerSignedAt,
    this.tenantSignatureType,
    this.tenantSignatureData,
    this.tenantSignedAt,
    this.createdAt,
    this.updatedAt,
    this.expiresAt,
    this.statusReason,
    this.statusChangedBy,
    this.statusChangedAt,
  });

  bool get ownerHasSigned => ownerSignedAt != null;
  bool get tenantHasSigned => tenantSignedAt != null;
  bool get hasDraft => terms != null && terms!.isNotEmpty;

  /// Name of whoever rejected/cancelled it, or null (system / unknown).
  String? get statusChangedByName {
    if (statusChangedBy == null || statusChangedBy!.isEmpty) return null;
    if (statusChangedBy == ownerId) return ownerName;
    if (statusChangedBy == tenantId) return tenantName;
    return null;
  }

  factory Agreement.fromJson(Map<String, dynamic> json) {
    SignatureType? parseSigType(String? v) =>
        v == null || v.isEmpty ? null : (v == 'draw' ? SignatureType.draw : SignatureType.type);

    return Agreement(
      id: json['id'] as String,
      propertyId: json['property_id'] as String,
      propertyTitle: json['property_title'] as String? ?? '',
      propertyImageUrl: json['property_image_url'] as String? ?? '',
      ownerId: json['owner_id'] as String,
      ownerName: json['owner_name'] as String? ?? '',
      tenantId: json['tenant_id'] as String,
      tenantName: json['tenant_name'] as String? ?? '',
      status: AgreementStatusX.fromApi(json['status'] as String? ?? 'requested'),
      monthlyRent: (json['monthly_rent'] as num?)?.toDouble(),
      securityDeposit: (json['security_deposit'] as num?)?.toDouble(),
      startDate: json['start_date'] != null ? DateTime.tryParse(json['start_date']) : null,
      durationMonths: json['duration_months'] as int?,
      terms: json['terms'] as String?,
      ownerSignatureType: parseSigType(json['owner_signature_type'] as String?),
      ownerSignatureData: json['owner_signature_data'] as String?,
      ownerSignedAt: json['owner_signed_at'] != null ? DateTime.tryParse(json['owner_signed_at']) : null,
      tenantSignatureType: parseSigType(json['tenant_signature_type'] as String?),
      tenantSignatureData: json['tenant_signature_data'] as String?,
      tenantSignedAt: json['tenant_signed_at'] != null ? DateTime.tryParse(json['tenant_signed_at']) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at']) : null,
      expiresAt: json['expires_at'] != null ? DateTime.tryParse(json['expires_at']) : null,
      statusReason: json['status_reason'] as String?,
      statusChangedBy: json['status_changed_by'] as String?,
      statusChangedAt: json['status_changed_at'] != null ? DateTime.tryParse(json['status_changed_at']) : null,
    );
  }
}