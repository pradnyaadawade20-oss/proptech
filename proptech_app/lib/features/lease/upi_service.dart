import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';

/// What the server decided for one UPI payment (UPI id + amount are NOT editable by the tenant).
class UpiLink {
  final String upiId, payeeName, note, link;
  final double amount;
  const UpiLink({required this.upiId, required this.payeeName, required this.note, required this.link, required this.amount});

  factory UpiLink.fromJson(Map<String, dynamic> j) => UpiLink(
        upiId: j['upi_id']?.toString() ?? '',
        payeeName: j['payee_name']?.toString() ?? '',
        note: j['note']?.toString() ?? '',
        link: j['link']?.toString() ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
      );
}

class UpiService {
  UpiService._();
  static final UpiService instance = UpiService._();

  final Dio _dio = ApiClient.instance.dio;

  Exception _err(DioException e) {
    var data = e.response?.data;
    if (data is List<int>) {
      try {
        data = jsonDecode(utf8.decode(data));
      } catch (_) {}
    }
    final msg = (data is Map && data['error'] != null) ? data['error'].toString() : (e.message ?? 'Something went wrong.');
    return Exception(msg);
  }

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  // ---- owner UPI id ----
  Future<String> ownerUpi() => _run(() async {
        final r = await _dio.get('/api/owner/upi');
        return r.data['upi_id']?.toString() ?? '';
      });

  Future<String> saveOwnerUpi(String upi) => _run(() async {
        final r = await _dio.put('/api/owner/upi', data: {'upi_id': upi});
        return r.data['upi_id']?.toString() ?? upi;
      });

  // ---- pay link ----
  Future<UpiLink> rentLink(String paymentId) => _run(() async {
        final r = await _dio.get('/api/rent/$paymentId/upi-link');
        return UpiLink.fromJson(r.data as Map<String, dynamic>);
      });

  Future<UpiLink> depositLink(String leaseId) => _run(() async {
        final r = await _dio.get('/api/leases/$leaseId/deposit/upi-link');
        return UpiLink.fromJson(r.data as Map<String, dynamic>);
      });

  // ---- submit UTR + screenshot ----
  Future<FormData> _form(String utr, XFile shot) async => FormData.fromMap({
        'utr': utr,
        'screenshot': MultipartFile.fromBytes(await shot.readAsBytes(), filename: shot.name.isEmpty ? 'proof.jpg' : shot.name),
      });

  Future<void> submitRent(String paymentId, String utr, XFile shot) =>
      _run(() async => _dio.post('/api/rent/$paymentId/upi-submit', data: await _form(utr, shot)));

  Future<void> submitDeposit(String leaseId, String utr, XFile shot) =>
      _run(() async => _dio.post('/api/leases/$leaseId/deposit/upi-submit', data: await _form(utr, shot)));

  // ---- proof / receipt ----
  Future<Uint8List> _bytes(String path) => _run(() async {
        final r = await _dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
        return Uint8List.fromList(r.data ?? const []);
      });

  Future<Uint8List> rentProof(String paymentId) => _bytes('/api/rent/$paymentId/proof');
  Future<Uint8List> depositProof(String leaseId) => _bytes('/api/leases/$leaseId/deposit/proof');
  Future<Uint8List> depositReceiptPdf(String leaseId) => _bytes('/api/leases/$leaseId/deposit/receipt');
}