import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import 'lease_models.dart';

/// Talks to /api/leases/*, /api/rent/* and /api/agreements/:id/lease.
class LeaseService {
  LeaseService._();
  static final LeaseService instance = LeaseService._();

  final Dio _dio = ApiClient.instance.dio;

  /// Base URL, used to build absolute photo URLs.
  String get baseUrl => _dio.options.baseUrl;

  Exception _err(DioException e) {
    var data = e.response?.data;
    if (data is List<int>) {
      try {
        data = jsonDecode(utf8.decode(data));
      } catch (_) {}
    }
    final msg = (data is Map && data['error'] != null)
        ? data['error'].toString()
        : (e.message ?? 'Something went wrong.');
    return Exception(msg);
  }

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  // ---------------- leases ----------------

  Future<List<Lease>> myLeases() => _run(() async {
        final r = await _dio.get('/api/leases');
        return ((r.data['leases'] as List?) ?? const [])
            .map((e) => Lease.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<Lease> leaseForAgreement(String agreementId) => _run(() async {
        final r = await _dio.get('/api/agreements/$agreementId/lease');
        return Lease.fromJson(r.data['lease'] as Map<String, dynamic>);
      });

  /// Returns the lease and the caller's role on it ("owner" | "tenant").
  Future<(Lease, String)> getLease(String id) => _run(() async {
        final r = await _dio.get('/api/leases/$id');
        return (Lease.fromJson(r.data['lease'] as Map<String, dynamic>), (r.data['role'] ?? '').toString());
      });

  Future<List<LeaseEvent>> events(String id) => _run(() async {
        final r = await _dio.get('/api/leases/$id/events');
        return ((r.data['events'] as List?) ?? const [])
            .map((e) => LeaseEvent.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  // ---------------- rent ----------------

  Future<(List<RentPayment>, RentSummary)> rent(String leaseId) => _run(() async {
        final r = await _dio.get('/api/leases/$leaseId/rent');
        final list = ((r.data['payments'] as List?) ?? const [])
            .map((e) => RentPayment.fromJson(e as Map<String, dynamic>))
            .toList();
        final sum = r.data['summary'] is Map
            ? RentSummary.fromJson(r.data['summary'] as Map<String, dynamic>)
            : const RentSummary();
        return (list, sum);
      });

  Future<void> payRent(String paymentId, String method, String reference) =>
      _run(() => _dio.post('/api/rent/$paymentId/pay', data: {'method': method, 'reference': reference}));

  Future<void> confirmRent(String paymentId) => _run(() => _dio.post('/api/rent/$paymentId/confirm', data: {}));

  Future<void> markRentPaid(String paymentId, String method, String reference) =>
      _run(() => _dio.post('/api/rent/$paymentId/mark-paid', data: {'method': method, 'reference': reference}));

  Future<void> rejectRent(String paymentId, String reason) =>
      _run(() => _dio.post('/api/rent/$paymentId/reject', data: {'reason': reason}));

  Future<Uint8List> receiptPdf(String paymentId) => _run(() async {
        final r = await _dio.get<List<int>>('/api/rent/$paymentId/receipt',
            options: Options(responseType: ResponseType.bytes));
        return Uint8List.fromList(r.data ?? const []);
      });

  // ---------------- renewal / move in-out ----------------

  Future<void> requestRenewal(String leaseId) =>
      _run(() => _dio.post('/api/leases/$leaseId/renewal', data: {'decision': 'renew'}));

  Future<void> giveNotice(String leaseId, String moveOutDate) =>
      _run(() => _dio.post('/api/leases/$leaseId/move-out', data: {'move_out_date': moveOutDate}));

  /// Returns the new agreement id when accepted (else null).
  Future<String?> respondRenewal(String leaseId, bool accept, {double? rent, int? months}) => _run(() async {
        final r = await _dio.post('/api/leases/$leaseId/renewal/respond', data: {
          'accept': accept,
          if (rent != null) 'monthly_rent': rent,
          if (months != null) 'duration_months': months,
        });
        final id = r.data['new_agreement_id']?.toString() ?? '';
        return id.isEmpty ? null : id;
      });

  Future<void> completeMoveOut(String leaseId) =>
      _run(() => _dio.post('/api/leases/$leaseId/move-out/complete', data: {}));

  Future<void> confirmMoveIn(String leaseId) =>
      _run(() => _dio.post('/api/leases/$leaseId/move-in/confirm', data: {}));

  // ---------------- deposit ----------------

  Future<Deposit?> deposit(String leaseId) => _run(() async {
        final r = await _dio.get('/api/leases/$leaseId/deposit');
        final d = r.data['deposit'];
        return d is Map<String, dynamic> ? Deposit.fromJson(d) : null;
      });

  Future<void> depositPay(String leaseId, String method, String reference) =>
      _run(() => _dio.post('/api/leases/$leaseId/deposit/pay', data: {'method': method, 'reference': reference}));

  Future<void> depositConfirm(String leaseId) =>
      _run(() => _dio.post('/api/leases/$leaseId/deposit/confirm', data: {}));

  Future<void> depositReject(String leaseId) =>
      _run(() => _dio.post('/api/leases/$leaseId/deposit/reject', data: {}));

  Future<void> startInspection(String leaseId) =>
      _run(() => _dio.post('/api/leases/$leaseId/deposit/inspection', data: {}));

  Future<void> addDeduction(
    String leaseId, {
    required String category,
    required String reason,
    required double amount,
    List<XFile> photos = const [],
  }) =>
      _run(() async {
        final form = FormData.fromMap({
          'category': category,
          'reason': reason,
          'amount': amount.toString(),
        });
        for (final p in photos) {
          form.files.add(MapEntry('images', MultipartFile.fromBytes(await p.readAsBytes(), filename: p.name)));
        }
        await _dio.post('/api/leases/$leaseId/deposit/deductions', data: form);
      });

  Future<void> deleteDeduction(String leaseId, String deductionId) =>
      _run(() => _dio.delete('/api/leases/$leaseId/deposit/deductions/$deductionId'));

  Future<void> sendSettlement(String leaseId) =>
      _run(() => _dio.post('/api/leases/$leaseId/deposit/settlement', data: {}));

  Future<void> respondSettlement(String leaseId, bool accept, String note) =>
      _run(() => _dio.post('/api/leases/$leaseId/deposit/respond', data: {'accept': accept, 'note': note}));

  Future<void> depositRefund(String leaseId, String method, String reference) =>
      _run(() => _dio.post('/api/leases/$leaseId/deposit/refund', data: {'method': method, 'reference': reference}));

  // ---------------- photos ----------------

  Future<List<RoomComparison>> comparison(String leaseId) => _run(() async {
        final r = await _dio.get('/api/leases/$leaseId/comparison');
        return ((r.data['rooms'] as List?) ?? const [])
            .map((e) => RoomComparison.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<void> uploadPhotos(String leaseId,
          {required String kind, required String room, String caption = '', required List<XFile> files}) =>
      _run(() async {
        final form = FormData.fromMap({'kind': kind, 'room': room, 'caption': caption});
        for (final p in files) {
          form.files.add(MapEntry('images', MultipartFile.fromBytes(await p.readAsBytes(), filename: p.name)));
        }
        await _dio.post('/api/leases/$leaseId/photos', data: form);
      });

  Future<void> deletePhoto(String leaseId, String photoId) =>
      _run(() => _dio.delete('/api/leases/$leaseId/photos/$photoId'));
}