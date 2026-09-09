import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';
import '../../native/acoustic_channel.dart';

class RelayLogEntry {
  final String id;
  final String text;
  final String status;
  final bool crcValid;
  final int bytes;
  final double signalLevel;
  final double distanceMeters;
  final DateTime timestamp;
  final bool isLoopback;
  final bool isSuppressed;

  RelayLogEntry({
    required this.id,
    required this.text,
    required this.status,
    required this.crcValid,
    required this.bytes,
    required this.signalLevel,
    required this.distanceMeters,
    required this.timestamp,
    this.isLoopback = false,
    this.isSuppressed = false,
  });
}

class AcousticRelayScreen extends StatefulWidget {
  const AcousticRelayScreen({super.key});

  @override
  State<AcousticRelayScreen> createState() => _AcousticRelayScreenState();
}

class _AcousticRelayScreenState extends State<AcousticRelayScreen> with SingleTickerProviderStateMixin {
  StreamSubscription? _eventSubscription;
  bool _isRelayActive = false;
  int _guardDelayMs = 500;
  int _repetitions = 1;
  bool _relayPrivate = true;

  // Telemetry
  double _signalLevel = 0.0;
  bool _hasSignal = false;
  double _distanceMeters = 5.0;
  String _proximityZone = 'STANDBY';
  double _snrDb = 0.0;
  String _engineState = 'IDLE';

  // Statistics
  int _packetsCaptured = 0;
  int _packetsVerified = 0;
  int _packetsRetransmitted = 0;
  int _duplicatesSuppressed = 0;

  // Pipeline Animation Stage (0: Idle, 1: Capture, 2: Demod, 3: CRC Verify, 4: Synthesize, 5: Speaker TX)
  int _activePipelineStage = 0;
  Timer? _stageResetTimer;

  // Node Info
  String _deviceName = 'Loading...';
  String _deviceIdHex = '...';

  final List<RelayLogEntry> _activityLogs = [];
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _loadIdentity();
    _checkInitialState();
    _listenToEvents();
  }

  Future<void> _loadIdentity() async {
    final id = await AcousticChannel.instance.getIdentity();
    if (mounted) {
      setState(() {
        _deviceName = id['deviceName'] as String? ?? 'Sonic Relay';
        _deviceIdHex = id['deviceIdHex'] as String? ?? '0000-0000';
      });
    }
  }

  Future<void> _checkInitialState() async {
    final stats = await AcousticChannel.instance.getRelayStats();
    if (mounted && stats.isNotEmpty) {
      setState(() {
        _isRelayActive = stats['isRelayMode'] as bool? ?? false;
        _packetsCaptured = (stats['packetsCaptured'] as num?)?.toInt() ?? 0;
        _packetsVerified = (stats['packetsVerified'] as num?)?.toInt() ?? 0;
        _packetsRetransmitted = (stats['packetsRetransmitted'] as num?)?.toInt() ?? 0;
        _duplicatesSuppressed = (stats['duplicatesSuppressed'] as num?)?.toInt() ?? 0;
      });
    }
  }

  void _listenToEvents() {
    _eventSubscription = AcousticChannel.instance.events.listen((event) {
      if (!mounted) return;
      final type = event['type'] as String?;

      if (type == 'STATE_CHANGED') {
        setState(() {
          _engineState = event['state'] as String? ?? 'IDLE';
        });
      } else if (type == 'SIGNAL_METRICS') {
        setState(() {
          _signalLevel = ((event['signalLevel'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 100.0);
          _hasSignal = event['hasSignal'] as bool? ?? false;
          _distanceMeters = ((event['estimatedDistanceMeters'] as num?)?.toDouble() ?? 5.0);
          _proximityZone = event['proximityZone'] as String? ?? 'STANDBY';
          _snrDb = ((event['snrDb'] as num?)?.toDouble() ?? 0.0);
        });
        if (_hasSignal && _activePipelineStage == 0 && _isRelayActive) {
          _setPipelineStage(1); // Stage 1: Audio Capture
        }
      } else if (type == 'RELAY_PACKET_QUEUED') {
        final text = event['payloadText'] as String? ?? '';
        final bytes = (event['bytes'] as num?)?.toInt() ?? text.length;
        _updateStatsFromMap(event['stats'] as Map?);

        _setPipelineStage(3); // Stage 3: CRC Verified
        HapticFeedback.lightImpact();

        setState(() {
          _activityLogs.insert(
            0,
            RelayLogEntry(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              text: text,
              status: 'CRC32 Verified -> Synthesizing FSK Signal...',
              crcValid: true,
              bytes: bytes,
              signalLevel: _signalLevel,
              distanceMeters: _distanceMeters,
              timestamp: DateTime.now(),
            ),
          );
        });
      } else if (type == 'RELAY_TX_STARTED') {
        final text = event['payloadText'] as String? ?? '';
        final bytes = (event['bytes'] as num?)?.toInt() ?? text.length;
        _updateStatsFromMap(event['stats'] as Map?);

        _setPipelineStage(5); // Stage 5: Speaker TX (Fresh FSK wave)
        HapticFeedback.mediumImpact();

        setState(() {
          if (_activityLogs.isNotEmpty && _activityLogs.first.text == text) {
            _activityLogs[0] = RelayLogEntry(
              id: _activityLogs.first.id,
              text: text,
              status: 'Transmitting Fresh Waveform (100% Power)',
              crcValid: true,
              bytes: bytes,
              signalLevel: _signalLevel,
              distanceMeters: _distanceMeters,
              timestamp: _activityLogs.first.timestamp,
            );
          }
        });
      } else if (type == 'RELAY_TX_COMPLETED') {
        final text = event['payloadText'] as String? ?? '';
        _updateStatsFromMap(event['stats'] as Map?);

        HapticFeedback.heavyImpact();

        setState(() {
          if (_activityLogs.isNotEmpty && _activityLogs.first.text == text) {
            _activityLogs[0] = RelayLogEntry(
              id: _activityLogs.first.id,
              text: text,
              status: 'RELAYED TO DESTINATION (Fresh Signal Broadcast)',
              crcValid: true,
              bytes: _activityLogs.first.bytes,
              signalLevel: _activityLogs.first.signalLevel,
              distanceMeters: _activityLogs.first.distanceMeters,
              timestamp: _activityLogs.first.timestamp,
            );
          }
        });

        _resetPipelineAfter(1200);
      } else if (type == 'RELAY_DUPLICATE_SUPPRESSED') {
        final text = event['payloadText'] as String? ?? '';
        _updateStatsFromMap(event['stats'] as Map?);

        setState(() {
          _activityLogs.insert(
            0,
            RelayLogEntry(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              text: text,
              status: 'DUPLICATE SUPPRESSED (Feedback Loop Blocked)',
              crcValid: true,
              bytes: text.length,
              signalLevel: _signalLevel,
              distanceMeters: _distanceMeters,
              timestamp: DateTime.now(),
              isSuppressed: true,
            ),
          );
        });
        _resetPipelineAfter(800);
      } else if (type == 'RELAY_MODE_CHANGED') {
        final active = event['isRelayMode'] as bool? ?? false;
        _updateStatsFromMap(event['stats'] as Map?);
        setState(() {
          _isRelayActive = active;
        });
      }
    });
  }

  void _updateStatsFromMap(Map? stats) {
    if (stats == null) return;
    setState(() {
      _packetsCaptured = (stats['packetsCaptured'] as num?)?.toInt() ?? _packetsCaptured;
      _packetsVerified = (stats['packetsVerified'] as num?)?.toInt() ?? _packetsVerified;
      _packetsRetransmitted = (stats['packetsRetransmitted'] as num?)?.toInt() ?? _packetsRetransmitted;
      _duplicatesSuppressed = (stats['duplicatesSuppressed'] as num?)?.toInt() ?? _duplicatesSuppressed;
    });
  }

  void _setPipelineStage(int stage) {
    _stageResetTimer?.cancel();
    setState(() {
      _activePipelineStage = stage;
    });
  }

  void _resetPipelineAfter(int ms) {
    _stageResetTimer?.cancel();
    _stageResetTimer = Timer(Duration(milliseconds: ms), () {
      if (mounted) {
        setState(() {
          _activePipelineStage = 0;
        });
      }
    });
  }

  Future<void> _toggleRelayMode() async {
    if (_isRelayActive) {
      await AcousticChannel.instance.stopRelayMode();
      setState(() {
        _isRelayActive = false;
        _activePipelineStage = 0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: SonicTheme.surfaceElevated,
            content: Text('Acoustic Relay Node Standby', style: TextStyle(color: SonicTheme.textSecondary)),
          ),
        );
      }
    } else {
      final granted = await AcousticChannel.instance.hasAudioPermission() ||
          await AcousticChannel.instance.requestAudioPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: SonicTheme.coral,
              content: Text('Microphone permission required for Relay Node'),
            ),
          );
        }
        return;
      }

      await AcousticChannel.instance.startRelayMode(
        guardDelayMs: _guardDelayMs,
        repetitions: _repetitions,
        relayPrivate: _relayPrivate,
      );
      setState(() {
        _isRelayActive = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: SonicTheme.teal,
            content: Text('Acoustic Relay Active: Listening for Phone A signals...'),
          ),
        );
      }
    }
  }

  Future<void> _runPipelineSimulation() async {
    _setPipelineStage(1);
    await Future.delayed(const Duration(milliseconds: 300));
    _setPipelineStage(2);
    await Future.delayed(const Duration(milliseconds: 300));
    _setPipelineStage(3);

    final res = await AcousticChannel.instance.testRelayPipeline(
      'Test Relay: A -> B -> C verified at ${DateTime.now().second}s',
    );

    if (res['success'] != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: SonicTheme.coral,
          content: Text('Simulation error: ${res['error'] ?? 'Unknown'}'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _stageResetTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ACOUSTIC RELAY',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.0),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: SonicTheme.cyan),
            tooltip: 'Relay Settings',
            onPressed: _showSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: SonicTheme.textMuted),
            tooltip: 'Clear Log',
            onPressed: () {
              setState(() => _activityLogs.clear());
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildRelayMasterCard(),
              const SizedBox(height: 14),
              _buildPipelineDiagramCard(),
              const SizedBox(height: 14),
              _buildCountersGrid(),
              const SizedBox(height: 14),
              _buildSignalTelemetryCard(),
              const SizedBox(height: 14),
              _buildActionButtons(),
              const SizedBox(height: 18),
              _buildSectionHeader('LIVE RELAY ACTIVITY STREAM'),
              const SizedBox(height: 10),
              _buildActivityLogs(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRelayMasterCard() {
    final activeColor = _isRelayActive ? SonicTheme.teal : SonicTheme.textMuted;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SonicTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isRelayActive ? SonicTheme.teal.withValues(alpha: 0.6) : SonicTheme.border,
          width: _isRelayActive ? 1.5 : 1.0,
        ),
        boxShadow: _isRelayActive
            ? [
                BoxShadow(
                  color: SonicTheme.teal.withValues(alpha: 0.15),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ]
            : null,
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: activeColor.withValues(alpha: _isRelayActive ? 0.15 + (_pulseController.value * 0.15) : 0.1),
                  border: Border.all(color: activeColor, width: 2),
                ),
                child: Icon(
                  Icons.repeat,
                  color: activeColor,
                  size: 24,
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Text(
                      _isRelayActive ? 'RELAY ACTIVE' : 'RELAY STANDBY',
                      style: TextStyle(
                        color: activeColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: activeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'NODE B',
                        style: TextStyle(color: activeColor, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _isRelayActive
                      ? 'Reconstructing: Phone A ➔ Node B ➔ Phone C'
                      : 'Switch ON to retransmit weak signals over distance',
                  style: const TextStyle(color: SonicTheme.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 3),
                Text(
                  '$_deviceName [$_deviceIdHex] • $_engineState',
                  style: const TextStyle(color: SonicTheme.cyan, fontSize: 10, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Switch(
            value: _isRelayActive,
            activeThumbColor: SonicTheme.teal,
            activeTrackColor: SonicTheme.teal.withValues(alpha: 0.5),
            onChanged: (val) => _toggleRelayMode(),
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineDiagramCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'SIGNAL RECONSTRUCTION PIPELINE',
                  style: TextStyle(
                    color: SonicTheme.cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: SonicTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'NO AUDIO REPLAY',
                  style: TextStyle(color: SonicTheme.amber, fontSize: 8.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPipelineNode(1, Icons.mic, '1. MIC', 'Weak Sig'),
                _buildPipelineArrow(1),
                _buildPipelineNode(2, Icons.graphic_eq, '2. DEMOD', 'FSK Tones'),
                _buildPipelineArrow(2),
                _buildPipelineNode(3, Icons.verified_user, '3. CRC32', '100% Valid'),
                _buildPipelineArrow(3),
                _buildPipelineNode(4, Icons.auto_awesome, '4. SYNTH', 'Fresh PCM'),
                _buildPipelineArrow(4),
                _buildPipelineNode(5, Icons.volume_up, '5. SPEAKER', 'To Phone C'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: SonicTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: SonicTheme.cyan, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isRelayActive
                        ? 'Phone B synthesizes a brand-new, clean CPFSK waveform from scratch and transmits at full acoustic power to Phone C.'
                        : 'Relay is on standby. Toggle switch above to activate continuous acoustic listening & re-broadcasting.',
                    style: const TextStyle(color: SonicTheme.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineNode(int stage, IconData icon, String label, String sub) {
    final isCurrent = _activePipelineStage == stage;
    final isPast = _activePipelineStage > stage;
    final Color nodeColor = isCurrent
        ? SonicTheme.teal
        : isPast
            ? SonicTheme.cyan
            : SonicTheme.textMuted;

    return SizedBox(
      width: 62,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: isCurrent ? SonicTheme.teal.withValues(alpha: 0.25) : SonicTheme.surfaceElevated,
              shape: BoxShape.circle,
              border: Border.all(
                color: nodeColor,
                width: isCurrent ? 2.0 : 1.0,
              ),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                        color: SonicTheme.teal.withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: Icon(icon, color: nodeColor, size: 16),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isCurrent ? SonicTheme.teal : SonicTheme.textPrimary,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isCurrent ? SonicTheme.teal : SonicTheme.textMuted,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineArrow(int afterStage) {
    final isActive = _activePipelineStage > afterStage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Icon(
        Icons.chevron_right,
        color: isActive ? SonicTheme.cyan : SonicTheme.textMuted.withValues(alpha: 0.4),
        size: 14,
      ),
    );
  }

  Widget _buildCountersGrid() {
    return Row(
      children: [
        Expanded(child: _buildCounterTile('HEARD', _packetsCaptured, SonicTheme.cyan, Icons.hearing)),
        const SizedBox(width: 6),
        Expanded(child: _buildCounterTile('VERIFIED', _packetsVerified, SonicTheme.teal, Icons.check_circle_outline)),
        const SizedBox(width: 6),
        Expanded(child: _buildCounterTile('RELAYED', _packetsRetransmitted, const Color(0xFF00E676), Icons.cell_tower)),
        const SizedBox(width: 6),
        Expanded(child: _buildCounterTile('SUPPRESSED', _duplicatesSuppressed, SonicTheme.amber, Icons.loop)),
      ],
    );
  }

  Widget _buildCounterTile(String title, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: SonicTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              count.toString(),
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              style: const TextStyle(
                color: SonicTheme.textMuted,
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalTelemetryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _hasSignal ? Icons.sensors : Icons.sensors_off,
                    color: _hasSignal ? SonicTheme.teal : SonicTheme.textMuted,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'ACOUSTIC CARRIER TELEMETRY',
                    style: TextStyle(color: SonicTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Text(
                'ZONE: $_proximityZone',
                style: TextStyle(
                  color: _hasSignal ? SonicTheme.teal : SonicTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (_signalLevel / 100.0).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: SonicTheme.surfaceElevated,
              valueColor: AlwaysStoppedAnimation<Color>(
                _signalLevel > 50 ? SonicTheme.teal : SonicTheme.cyan,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Signal Level: ${_signalLevel.toStringAsFixed(1)} dB',
                style: const TextStyle(color: SonicTheme.textSecondary, fontSize: 11),
              ),
              Text(
                'Est. Distance: ~${_distanceMeters.toStringAsFixed(1)}m',
                style: const TextStyle(color: SonicTheme.textSecondary, fontSize: 11),
              ),
              Text(
                'SNR: ${_snrDb.toStringAsFixed(1)} dB',
                style: const TextStyle(color: SonicTheme.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _runPipelineSimulation,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('TEST RELAY PIPELINE'),
            style: ElevatedButton.styleFrom(
              backgroundColor: SonicTheme.surfaceElevated,
              foregroundColor: SonicTheme.cyan,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: SonicTheme.cyan, width: 1),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _showSettingsDialog,
          icon: const Icon(Icons.tune, size: 18),
          label: const Text('CONFIG'),
          style: OutlinedButton.styleFrom(
            foregroundColor: SonicTheme.textSecondary,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            side: const BorderSide(color: SonicTheme.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: SonicTheme.cyan,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildActivityLogs() {
    if (_activityLogs.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        decoration: BoxDecoration(
          color: SonicTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SonicTheme.border),
        ),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.cell_tower, color: SonicTheme.textMuted.withValues(alpha: 0.5), size: 40),
            const SizedBox(height: 10),
            const Text(
              'Awaiting Acoustic Signals',
              style: TextStyle(color: SonicTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'When Phone A transmits within range, Phone B will decode, verify CRC32, and re-broadcast the fresh signal to Phone C.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SonicTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _activityLogs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final log = _activityLogs[index];
        final timeStr =
            '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: log.isSuppressed ? SonicTheme.surface : SonicTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: log.isSuppressed ? SonicTheme.amber.withValues(alpha: 0.4) : SonicTheme.teal.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: log.isSuppressed
                              ? SonicTheme.amber.withValues(alpha: 0.2)
                              : SonicTheme.teal.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          log.isSuppressed ? 'LOOP SUPPRESSED' : 'RELAY RETRANSMIT',
                          style: TextStyle(
                            color: log.isSuppressed ? SonicTheme.amber : SonicTheme.teal,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${log.bytes} B',
                        style: const TextStyle(color: SonicTheme.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                  Text(
                    timeStr,
                    style: const TextStyle(color: SonicTheme.textMuted, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                log.text,
                style: const TextStyle(
                  color: SonicTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    log.crcValid ? Icons.check_circle : Icons.error_outline,
                    color: log.crcValid ? SonicTheme.teal : SonicTheme.coral,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      log.status,
                      style: TextStyle(
                        color: log.isSuppressed ? SonicTheme.amber : SonicTheme.teal,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSettingsDialog() {
    int tempDelay = _guardDelayMs;
    int tempRep = _repetitions;
    bool tempPriv = _relayPrivate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: SonicTheme.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Relay Node Configuration',
            style: TextStyle(color: SonicTheme.cyan, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Turnaround Guard Delay:',
                style: TextStyle(color: SonicTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const Text(
                'Silence interval before Phone B retransmits, allowing acoustic echo clearance.',
                style: TextStyle(color: SonicTheme.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [300, 500, 800, 1000].map((ms) {
                  final isSelected = tempDelay == ms;
                  return ChoiceChip(
                    label: Text('${ms}ms${ms == 500 ? ' (Rec)' : ''}'),
                    selected: isSelected,
                    selectedColor: SonicTheme.cyan,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : SonicTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setDialogState(() => tempDelay = ms);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Retransmission Redundancy:',
                style: TextStyle(color: SonicTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [1, 2, 3].map((rep) {
                  final isSelected = tempRep == rep;
                  return ChoiceChip(
                    label: Text('${rep}x Fresh Signal'),
                    selected: isSelected,
                    selectedColor: SonicTheme.teal,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : SonicTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setDialogState(() => tempRep = rep);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Relay Private Messages',
                  style: TextStyle(color: SonicTheme.textPrimary, fontSize: 12),
                ),
                subtitle: const Text(
                  'Forward unicast packets towards recipient node',
                  style: TextStyle(color: SonicTheme.textMuted, fontSize: 10),
                ),
                value: tempPriv,
                activeColor: SonicTheme.teal,
                onChanged: (val) {
                  setDialogState(() => tempPriv = val ?? true);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL', style: TextStyle(color: SonicTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() {
                  _guardDelayMs = tempDelay;
                  _repetitions = tempRep;
                  _relayPrivate = tempPriv;
                });
                if (_isRelayActive) {
                  await AcousticChannel.instance.startRelayMode(
                    guardDelayMs: _guardDelayMs,
                    repetitions: _repetitions,
                    relayPrivate: _relayPrivate,
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: SonicTheme.cyan, foregroundColor: Colors.black),
              child: const Text('APPLY'),
            ),
          ],
        ),
      ),
    );
  }
}
