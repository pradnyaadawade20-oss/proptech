import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../chat/chat_avatar.dart';
import 'call_service.dart';

/// Full-screen in-app call UI (outgoing, incoming and in-call).
class CallScreen extends StatefulWidget {
  final String callId;
  const CallScreen({super.key, required this.callId});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallService _call = CallService.instance;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _call.screenOpen = true;
    _call.addListener(_onChange);
    // Opened from a push notification (no live "incoming" event happened).
    if (_call.callId != widget.callId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _call.loadIncoming(widget.callId));
    }
  }

  @override
  void dispose() {
    _call.removeListener(_onChange);
    _call.screenOpen = false;
    Future.microtask(_call.clearIfEnded); // not during dispose: it notifies listeners
    super.dispose();
  }

  void _onChange() {
    if (_call.phase == CallPhase.ended && !_closing) {
      _closing = true;
      Timer(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(RouteNames.home);
        }
      });
    }
  }

  String _status() {
    switch (_call.phase) {
      case CallPhase.outgoingRinging:
        return 'Calling…';
      case CallPhase.incomingRinging:
        return 'Incoming call';
      case CallPhase.connecting:
        return 'Connecting…';
      case CallPhase.active:
        final d = _call.duration;
        final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
        final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
        return d.inHours > 0 ? '${d.inHours}:$mm:$ss' : '$mm:$ss';
      case CallPhase.ended:
        return _call.endReason.isEmpty ? 'Call ended' : _call.endReason;
      case CallPhase.idle:
        return 'Loading…';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _call,
      builder: (context, _) {
        final phase = _call.phase;
        final name = _call.peerName.isEmpty ? 'PropTech user' : _call.peerName;
        final canLeave = phase == CallPhase.ended || phase == CallPhase.idle;

        return PopScope(
          canPop: canLeave,
          child: Scaffold(
            body: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.primaryDark, AppColors.primary],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 72),
                    ChatAvatar(name: name, avatarUrl: '', radius: 56),
                    const SizedBox(height: 24),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status(),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 16),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 56),
                      child: _controls(phase),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _controls(CallPhase phase) {
    if (phase == CallPhase.incomingRinging) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(icon: Icons.call_end, color: Colors.red, label: 'Decline', onTap: _call.reject),
          _RoundButton(icon: Icons.call, color: Colors.green, label: 'Accept', onTap: _call.accept),
        ],
      );
    }
    if (phase == CallPhase.ended || phase == CallPhase.idle) {
      return const SizedBox(height: 72);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          icon: _call.muted ? Icons.mic_off : Icons.mic,
          color: _call.muted ? Colors.white : Colors.white24,
          iconColor: _call.muted ? AppColors.primaryDark : Colors.white,
          label: _call.muted ? 'Unmute' : 'Mute',
          onTap: _call.toggleMute,
        ),
        _RoundButton(icon: Icons.call_end, color: Colors.red, label: 'End', onTap: _call.hangUp),
        _RoundButton(
          icon: _call.speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded, // speaker on -> speaker, else earpiece (ear)
          color: _call.speakerOn ? Colors.white : Colors.white24,
          iconColor: _call.speakerOn ? AppColors.primaryDark : Colors.white,
          label: _call.speakerOn ? 'Speaker' : 'Earpiece',
          onTap: _call.toggleSpeaker,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _RoundButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 72, height: 72, child: Icon(icon, color: iconColor, size: 32)),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ],
    );
  }
}