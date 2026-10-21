import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../app/router/app_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/token_store.dart';
import '../notifications/push_notification_service.dart';

enum CallPhase { idle, outgoingRinging, incomingRinging, connecting, active, ended }

/// In-app peer-to-peer audio calls (WebRTC).
///
/// The backend only does signaling (WebSocket `/ws/calls`) + call log
/// (`/api/calls`). Audio goes phone <-> phone. One call at a time.
///
/// Usage:
///   * `CallService.instance.connect()` after login, `disconnect()` on logout.
///   * `CallService.dial(context, ...)` from any "Call" button.
///   * Incoming calls open `/call/:id` automatically.
class CallService extends ChangeNotifier {
  CallService._();
  static final CallService instance = CallService._();

  Dio get _dio => ApiClient.instance.dio;

  // ------------------------------------------------------------ public state
  CallPhase phase = CallPhase.idle;
  String? callId;
  bool isCaller = false;
  String peerName = '';
  String endReason = '';
  bool muted = false;
  bool speakerOn = false;
  Duration duration = Duration.zero;

  /// Set by CallScreen so we don't push the same screen twice.
  bool screenOpen = false;

  bool get busy => phase != CallPhase.idle && phase != CallPhase.ended;
  bool get isConnected => _channel != null;

  // ------------------------------------------------------------ websocket
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _wantConnected = false;
  bool _opening = false;
  int _backoffSec = 1;

  // ------------------------------------------------------------ webrtc
  RTCPeerConnection? _pc;
  MediaStream? _local;
  List<Map<String, dynamic>> _ice = [];
  final List<RTCIceCandidate> _pendingIce = [];
  bool _remoteSet = false;

  Timer? _tick;
  Timer? _ringBuzz;
  Timer? _connectTimeout;
  DateTime? _connectedAt;

  // =====================================================================
  // Connection lifecycle
  // =====================================================================

  Future<void> connect() async {
    _wantConnected = true;
    if (_channel != null || _opening) return;
    await _open();
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    if (busy) _hangUpLocal('Call ended');
    _closeSocket();
  }

  String get _wsUrl => '${ApiClient.baseUrl.replaceFirst('http', 'ws')}/ws/calls';

  Future<void> _open() async {
    _opening = true;
    try {
      final token = await TokenStore.instance.getToken();
      if (token == null) return;
      final ch = WebSocketChannel.connect(
        Uri.parse('$_wsUrl?token=${Uri.encodeQueryComponent(token)}'),
      );
      await ch.ready.timeout(const Duration(seconds: 20));
      _channel = ch;
      _backoffSec = 1;
      _sub = ch.stream.listen(
        _onData,
        onDone: _onSocketClosed,
        onError: (_) => _onSocketClosed(),
      );
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) => _send({'type': 'ping'}));
    } catch (e) {
      debugPrint('call socket failed: $e');
      _scheduleReconnect();
    } finally {
      _opening = false;
    }
  }

  void _closeSocket() {
    _pingTimer?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _onSocketClosed() {
    _closeSocket();
    // The server ends open calls when our socket drops.
    if (busy) _hangUpLocal('Connection lost');
    if (_wantConnected) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_wantConnected) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _backoffSec), _open);
    _backoffSec = (_backoffSec * 2).clamp(1, 30).toInt();
  }

  Future<bool> _ensureConnected() async {
    _wantConnected = true;
    if (_channel == null && !_opening) await _open();
    return _channel != null;
  }

  bool _send(Map<String, dynamic> msg) {
    final ch = _channel;
    if (ch == null) return false;
    try {
      ch.sink.add(jsonEncode(msg));
      return true;
    } catch (_) {
      return false;
    }
  }

  // =====================================================================
  // Starting / answering calls
  // =====================================================================

  /// Convenience for every "Call" button: starts the call and opens the screen.
  /// Send ONE of: [leadId], [propertyId] (buyer on a listing), or
  /// [propertyId] + [peerId] / just [peerId] (chat).
  static Future<void> dial(
    BuildContext context, {
    String? leadId,
    String? propertyId,
    String? peerId,
    String peerName = '',
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await instance.startCall(
        leadId: leadId,
        propertyId: propertyId,
        peerId: peerId,
        peerName: peerName,
      );
      appRouter.push('/call/$id');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  static String _msg(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['error'] is String) return d['error'] as String;
      return 'Network error. Please try again.';
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<String> startCall({
    String? leadId,
    String? propertyId,
    String? peerId,
    String peerName = '',
  }) async {
    if (busy) throw Exception('You are already on a call.');
    if (!await _ensureConnected()) {
      throw Exception('Could not connect to the call server. Please try again.');
    }
    // Ask for the microphone BEFORE ringing the other person.
    final micError = await _micPermissionError();
    if (micError != null) throw Exception(micError);
    await _acquireMic();

    try {
      final res = await _dio.post('/api/calls', data: {
        if (leadId != null && leadId.isNotEmpty) 'lead_id': leadId,
        if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
        if (peerId != null && peerId.isNotEmpty) 'peer_id': peerId,
      });
      final data = res.data as Map<String, dynamic>;
      _ice = _parseIce(data['ice_servers']);
      _reset();
      callId = (data['call'] as Map)['id'] as String;
      isCaller = true;
      this.peerName = peerName;
      phase = CallPhase.outgoingRinging;
      notifyListeners();
      return callId!;
    } catch (e) {
      await _releaseMedia();
      rethrow;
    }
  }

  /// Called by the call screen when opened from a push (app was closed /
  /// background) and no live "incoming" event reached us.
  Future<void> loadIncoming(String id) async {
    if (callId == id && phase != CallPhase.idle) return;
    await _ensureConnected();
    try {
      final res = await _dio.get('/api/calls');
      final list = (res.data['calls'] as List?) ?? [];
      final c = list.cast<Map>().firstWhere((m) => m['id'] == id, orElse: () => {});
      if (c.isNotEmpty && c['status'] == 'ringing' && c['direction'] == 'incoming') {
        _reset();
        callId = id;
        isCaller = false;
        peerName = (c['peer_name'] as String?) ?? '';
        phase = CallPhase.incomingRinging;
        _startBuzz();
        notifyListeners();
        return;
      }
    } catch (_) {}
    _reset();
    callId = id;
    endReason = 'Call ended';
    phase = CallPhase.ended;
    notifyListeners();
  }

  Future<void> accept() async {
    if (phase != CallPhase.incomingRinging || callId == null) return;
    _stopBuzz();
    phase = CallPhase.connecting;
    notifyListeners();
    // Tells the user the real reason instead of always blaming the microphone.
    var failure = 'Could not answer the call';
    try {
      final micError = await _micPermissionError();
      if (micError != null) {
        failure = micError;
        throw Exception(micError);
      }
      failure = 'Could not connect. Check your internet and try again.';
      if (!await _ensureConnected()) throw Exception('No connection');
      final res = await _dio.get('/api/calls/ice-servers');
      _ice = _parseIce(res.data['ice_servers']);
      failure = 'Could not start the microphone. Please try again.';
      await _acquireMic();
      failure = 'Could not set up the call. Please try again.';
      await _createPeer();
      _send({'type': 'accept', 'call_id': callId});
      _startConnectTimeout();
    } catch (e) {
      debugPrint('accept failed: $e');
      _send({'type': 'reject', 'call_id': callId});
      _hangUpLocal(failure);
    }
  }

  Future<void> reject() async {
    final id = callId;
    if (id == null) return;
    if (!_send({'type': 'reject', 'call_id': id})) {
      try {
        await _dio.post('/api/calls/$id/reject');
      } catch (_) {}
    }
    _hangUpLocal('Call declined');
  }

  Future<void> hangUp() async {
    final id = callId;
    if (id != null) _send({'type': 'end', 'call_id': id});
    _hangUpLocal('Call ended');
  }

  void toggleMute() {
    muted = !muted;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    notifyListeners();
  }

  void toggleSpeaker() {
    speakerOn = !speakerOn;
    Helper.setSpeakerphoneOn(speakerOn);
    notifyListeners();
  }

  /// Screen calls this once it has closed after the call ended.
  void clearIfEnded() {
    if (phase == CallPhase.ended) {
      _reset();
      notifyListeners();
    }
  }

  // =====================================================================
  // Incoming socket messages
  // =====================================================================

  Future<void> _onData(dynamic raw) async {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = m['type'] as String?;
    final id = m['call_id'] as String?;
    final data = m['data'];

    switch (type) {
      case 'incoming':
        if (id == null) return;
        if (busy) {
          _send({'type': 'reject', 'call_id': id}); // already on a call
          return;
        }
        _reset();
        callId = id;
        isCaller = false;
        peerName = (data is Map ? data['caller_name'] as String? : null) ?? 'Someone';
        phase = CallPhase.incomingRinging;
        _startBuzz();
        notifyListeners();
        if (!screenOpen) appRouter.push('/call/$id');
        break;

      case 'accepted': // caller: callee picked up -> start WebRTC
        if (id != callId || !isCaller) return;
        phase = CallPhase.connecting;
        notifyListeners();
        try {
          await _createPeer();
          final offer = await _pc!.createOffer({'offerToReceiveAudio': 1});
          await _pc!.setLocalDescription(offer);
          _send({
            'type': 'offer',
            'call_id': callId,
            'data': {'sdp': offer.sdp, 'type': offer.type},
          });
          _startConnectTimeout();
        } catch (e) {
          debugPrint('offer failed: $e');
          hangUp();
        }
        break;

      case 'offer': // callee
        if (id != callId || _pc == null || data is! Map) return;
        await _pc!.setRemoteDescription(RTCSessionDescription(data['sdp'] as String?, data['type'] as String?));
        _remoteSet = true;
        final answer = await _pc!.createAnswer({'offerToReceiveAudio': 1});
        await _pc!.setLocalDescription(answer);
        _send({
          'type': 'answer',
          'call_id': callId,
          'data': {'sdp': answer.sdp, 'type': answer.type},
        });
        await _flushIce();
        break;

      case 'answer': // caller
        if (id != callId || _pc == null || data is! Map) return;
        await _pc!.setRemoteDescription(RTCSessionDescription(data['sdp'] as String?, data['type'] as String?));
        _remoteSet = true;
        await _flushIce();
        break;

      case 'ice':
        if (id != callId || data is! Map) return;
        final c = RTCIceCandidate(
          data['candidate'] as String?,
          data['sdpMid'] as String?,
          (data['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (_pc != null && _remoteSet) {
          await _pc!.addCandidate(c);
        } else {
          _pendingIce.add(c);
        }
        break;

      case 'ended':
        if (id != callId) return;
        _hangUpLocal(_reasonText(m['reason'] as String?));
        break;

      case 'error':
        debugPrint('call signaling error: ${m['reason']}');
        break;
    }
  }

  String _reasonText(String? r) {
    switch (r) {
      case 'rejected':
        return isCaller ? 'Call declined' : 'Call ended';
      case 'no_answer':
        return isCaller ? 'No answer' : 'Missed call';
      case 'cancelled':
        return isCaller ? 'Call cancelled' : 'Missed call';
      case 'peer_disconnected':
        return 'Connection lost';
      default:
        return 'Call ended';
    }
  }

  // =====================================================================
  // WebRTC
  // =====================================================================

  List<Map<String, dynamic>> _parseIce(dynamic raw) {
    if (raw is! List) {
      return [
        {'urls': ['stun:stun.l.google.com:19302']}
      ];
    }
    return raw.map<Map<String, dynamic>>((e) {
      final m = Map<String, dynamic>.from(e as Map);
      m.removeWhere((k, v) => v == null || v == '');
      return m;
    }).toList();
  }

  /// Asks for the microphone permission up-front (shows the system dialog).
  /// Returns null when granted, or a message to show the user.
  Future<String?> _micPermissionError() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return null;
    status = await Permission.microphone.request();
    if (status.isGranted) return null;
    if (status.isPermanentlyDenied) {
      return 'Microphone is blocked. Enable it in Settings > Apps > this app > Permissions > Microphone.';
    }
    return 'Microphone permission is needed for calls. Please allow it and try again.';
  }

  Future<void> _acquireMic() async {
    if (_local != null) return;
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
  }

  Future<void> _createPeer() async {
    await _acquireMic();
    final pc = await createPeerConnection({
      'iceServers': _ice,
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;
    for (final t in _local!.getAudioTracks()) {
      await pc.addTrack(t, _local!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _send({
        'type': 'ice',
        'call_id': callId,
        'data': {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex},
      });
    };
    pc.onIceConnectionState = (s) {
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _markActive();
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        hangUp();
        endReason = 'Could not connect';
        notifyListeners();
      }
    };
    await Helper.setSpeakerphoneOn(false);
    speakerOn = false;
  }

  Future<void> _flushIce() async {
    final pc = _pc;
    if (pc == null) return;
    for (final c in _pendingIce) {
      await pc.addCandidate(c);
    }
    _pendingIce.clear();
  }

  void _markActive() {
    if (phase == CallPhase.active) return;
    _connectTimeout?.cancel();
    phase = CallPhase.active;
    _connectedAt = DateTime.now();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      duration = DateTime.now().difference(_connectedAt!);
      notifyListeners();
    });
    notifyListeners();
  }

  void _startConnectTimeout() {
    _connectTimeout?.cancel();
    _connectTimeout = Timer(const Duration(seconds: 30), () {
      if (phase == CallPhase.connecting) {
        hangUp();
        endReason = 'Could not connect';
        notifyListeners();
      }
    });
  }

  // =====================================================================
  // Cleanup
  // =====================================================================

  void _hangUpLocal(String reason) {
    if (phase == CallPhase.ended || phase == CallPhase.idle) return;
    _stopBuzz();
    _tick?.cancel();
    _connectTimeout?.cancel();
    _releaseMedia();
    endReason = reason;
    phase = CallPhase.ended;
    notifyListeners();
    // If nobody has the call screen open, clear ourselves shortly.
    Future.delayed(const Duration(seconds: 3), () {
      if (!screenOpen) clearIfEnded();
    });
  }

  Future<void> _releaseMedia() async {
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _local?.dispose();
    } catch (_) {}
    _local = null;
    _pendingIce.clear();
    _remoteSet = false;
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}
  }

  void _reset() {
    _stopBuzz();
    _tick?.cancel();
    _connectTimeout?.cancel();
    phase = CallPhase.idle;
    callId = null;
    isCaller = false;
    peerName = '';
    endReason = '';
    muted = false;
    speakerOn = false;
    duration = Duration.zero;
    _connectedAt = null;
  }

  /// Incoming call: loop the phone's ringtone + vibrate until answered/ended.
  void _startBuzz() {
    _ringBuzz?.cancel();
    _playRing();
    HapticFeedback.vibrate();
    _ringBuzz = Timer.periodic(const Duration(milliseconds: 1500), (_) => HapticFeedback.vibrate());
  }

  AudioPlayer? _ringPlayer;

  static const MethodChannel _ringChannel = MethodChannel('proptech/ringtone');
  bool _nativeRinging = false;

  Future<void> _playRing() async {
    // Android: play the ringtone the user has set on the phone.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final ok = await _ringChannel.invokeMethod<bool>('play');
        if (ok == true) {
          _nativeRinging = true;
          // Call may have ended while we were starting.
          if (_ringBuzz == null) _stopRing();
          return;
        }
      } catch (e) {
        debugPrint('native ringtone failed: $e');
      }
    }
    // iOS (can't read the user's ringtone) / fallback: bundled tone.
    try {
      await _ringPlayer?.dispose();
      final p = AudioPlayer();
      _ringPlayer = p;
      await p.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.notificationRingtone, // follows the phone's ring volume
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gain,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
      ));
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(1.0);
      await p.play(AssetSource('audio/ringtone.wav'));
    } catch (e) {
      debugPrint('ringtone failed: $e');
    }
  }

  void _stopRing() {
    if (_nativeRinging) {
      _nativeRinging = false;
      _ringChannel.invokeMethod('stop').catchError((_) {});
    }
    final p = _ringPlayer;
    _ringPlayer = null;
    if (p == null) return;
    p.stop().whenComplete(p.dispose).catchError((_) {});
  }

  void _stopBuzz() {
    _ringBuzz?.cancel();
    _ringBuzz = null;
    _stopRing();
    // Remove the "Incoming call" notification (it rings until dismissed).
    PushNotificationService.instance.cancelCallNotification(callId);
  }
}