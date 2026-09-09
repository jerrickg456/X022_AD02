import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../native/acoustic_channel.dart';

class PersistentBroadcastScreen extends StatefulWidget {
  const PersistentBroadcastScreen({super.key});

  @override
  State<PersistentBroadcastScreen> createState() => _PersistentBroadcastScreenState();
}

class _PersistentBroadcastScreenState extends State<PersistentBroadcastScreen>
    with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController(text: 'HELLO MESH');

  // Duration presets in seconds
  static const List<_DurationPreset> _durationPresets = [
    _DurationPreset(label: '30s', seconds: 30),
    _DurationPreset(label: '1m', seconds: 60),
    _DurationPreset(label: '2m', seconds: 120),
    _DurationPreset(label: '5m', seconds: 300),
    _DurationPreset(label: 'Custom', seconds: -1),
  ];

  // Interval presets in seconds
  static const List<int> _intervalPresets = [3, 5, 10, 15];

  int _selectedDurationIndex = 1; // default: 1 minute
  int _customDurationSeconds = 90;
  int _selectedIntervalSeconds = 5;
  int _repetitions = 1;

  // Broadcast state
  bool _isBroadcasting = false;
  bool _isCurrentlyTransmitting = false;
  int _remainingSeconds = 0;
  int _totalDurationSeconds = 0;
  int _repeatCount = 0;
  double _txProgress = 0.0;
  String _statusText = 'Ready — Configure and start persistent broadcast';

  // Timers
  Timer? _countdownTimer;
  Timer? _retransmitTimer;
  StreamSubscription? _eventSubscription;

  // Animation
  late AnimationController _pulseController;
  late AnimationController _ringController;

  final List<String> _quickMessages = [
    'HELLO MESH',
    'SOS: Medical Needed Grid 4',
    'Rendezvous Point Alpha',
    'Grid Sector Clear',
    'Ping: Acoustic Beacon',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _eventSubscription = AcousticChannel.instance.events.listen(_handleEvent);
  }

  void _handleEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type'] as String?;

    if (type == 'TX_STARTED') {
      setState(() {
        _isCurrentlyTransmitting = true;
        _txProgress = 0.0;
      });
    } else if (type == 'TX_PROGRESS') {
      setState(() {
        _txProgress = (event['progress'] as num?)?.toDouble() ?? 0.0;
      });
    } else if (type == 'TX_COMPLETED') {
      setState(() {
        _isCurrentlyTransmitting = false;
        _txProgress = 1.0;
      });
      // Schedule next retransmit if still broadcasting
      _scheduleNextRetransmit();
    } else if (type == 'ERROR') {
      setState(() {
        _isCurrentlyTransmitting = false;
        _statusText = 'Error: ${event['message']}';
      });
    }
  }

  int get _effectiveDuration {
    final preset = _durationPresets[_selectedDurationIndex];
    return preset.seconds == -1 ? _customDurationSeconds : preset.seconds;
  }

  void _startPersistentBroadcast() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message to broadcast')),
      );
      return;
    }

    final duration = _effectiveDuration;

    setState(() {
      _isBroadcasting = true;
      _totalDurationSeconds = duration;
      _remainingSeconds = duration;
      _repeatCount = 0;
      _statusText = 'PERSISTENT BROADCAST ACTIVE';
    });

    // Start countdown timer (ticks every second)
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingSeconds--;
      });
      if (_remainingSeconds <= 0) {
        _stopPersistentBroadcast(completed: true);
      }
    });

    // Fire the first transmission immediately
    _transmitOnce();
  }

  void _transmitOnce() async {
    if (!_isBroadcasting || !mounted) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _repeatCount++;
      _isCurrentlyTransmitting = true;
      _txProgress = 0.0;
    });

    await AcousticChannel.instance.startBroadcast(text, repetitions: _repetitions);
    // TX_COMPLETED event will trigger _scheduleNextRetransmit
  }

  void _scheduleNextRetransmit() {
    if (!_isBroadcasting || !mounted) return;
    if (_remainingSeconds <= 0) return;

    // Cancel any existing retransmit timer
    _retransmitTimer?.cancel();

    // Wait for the configured interval before next retransmit
    _retransmitTimer = Timer(Duration(seconds: _selectedIntervalSeconds), () {
      if (_isBroadcasting && mounted && _remainingSeconds > 0) {
        _transmitOnce();
      }
    });
  }

  void _stopPersistentBroadcast({bool completed = false}) async {
    _countdownTimer?.cancel();
    _retransmitTimer?.cancel();
    _countdownTimer = null;
    _retransmitTimer = null;

    if (_isCurrentlyTransmitting) {
      await AcousticChannel.instance.stopBroadcast();
    }

    if (mounted) {
      setState(() {
        _isBroadcasting = false;
        _isCurrentlyTransmitting = false;
        _txProgress = 0.0;
        _statusText = completed
            ? 'Persistent broadcast completed — $_repeatCount transmissions sent'
            : 'Broadcast stopped — $_repeatCount transmissions sent';
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _retransmitTimer?.cancel();
    _pulseController.dispose();
    _ringController.dispose();
    _eventSubscription?.cancel();
    _textController.dispose();
    if (_isBroadcasting) {
      AcousticChannel.instance.stopBroadcast();
    }
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PERSISTENT BROADCAST'),
        actions: [
          if (_isBroadcasting)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: SonicTheme.coral.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SonicTheme.coral.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (_, __) => Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: SonicTheme.coral.withValues(
                              alpha: 0.5 + _pulseController.value * 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: SonicTheme.coral,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCountdownRing(),
              const SizedBox(height: 16),
              _buildStatusBanner(),
              const SizedBox(height: 16),
              if (_isBroadcasting) ...[
                _buildLiveStatsRow(),
                const SizedBox(height: 16),
                if (_isCurrentlyTransmitting) _buildTxProgressBar(),
                if (_isCurrentlyTransmitting) const SizedBox(height: 16),
              ],
              if (!_isBroadcasting) ...[
                _buildMessageInputCard(),
                const SizedBox(height: 14),
                _buildDurationSelector(),
                const SizedBox(height: 14),
                _buildIntervalSelector(),
                const SizedBox(height: 14),
                _buildRedundancySelector(),
                const SizedBox(height: 14),
                _buildQuickPresets(),
                const SizedBox(height: 18),
              ],
              _buildActionButton(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Countdown Ring ─────────────────────────────────────────────

  Widget _buildCountdownRing() {
    final progress = _totalDurationSeconds > 0
        ? _remainingSeconds / _totalDurationSeconds
        : 0.0;

    return Center(
      child: SizedBox(
        width: 180,
        height: 180,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Animated ring background
            if (_isBroadcasting)
              AnimatedBuilder(
                animation: _ringController,
                builder: (_, __) => CustomPaint(
                  size: const Size(180, 180),
                  painter: _PulseRingPainter(
                    progress: _ringController.value,
                    color: SonicTheme.amber,
                  ),
                ),
              ),
            // Progress arc
            SizedBox(
              width: 160,
              height: 160,
              child: CircularProgressIndicator(
                value: _isBroadcasting ? progress : 1.0,
                strokeWidth: 6,
                backgroundColor: SonicTheme.surfaceElevated,
                color: _isBroadcasting
                    ? (_remainingSeconds < 10 ? SonicTheme.coral : SonicTheme.amber)
                    : SonicTheme.border,
                strokeCap: StrokeCap.round,
              ),
            ),
            // Inner content
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isBroadcasting ? Icons.cell_tower : Icons.timer_outlined,
                  color: _isBroadcasting ? SonicTheme.amber : SonicTheme.textMuted,
                  size: 28,
                ),
                const SizedBox(height: 4),
                Text(
                  _isBroadcasting
                      ? _formatDuration(_remainingSeconds)
                      : _formatDuration(_effectiveDuration),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    color: _isBroadcasting
                        ? (_remainingSeconds < 10 ? SonicTheme.coral : SonicTheme.amber)
                        : SonicTheme.textSecondary,
                    letterSpacing: 2.0,
                  ),
                ),
                Text(
                  _isBroadcasting ? 'REMAINING' : 'DURATION',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: _isBroadcasting ? SonicTheme.amber : SonicTheme.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Status Banner ──────────────────────────────────────────────

  Widget _buildStatusBanner() {
    Color bannerColor;
    IconData bannerIcon;
    if (_isBroadcasting) {
      bannerColor = SonicTheme.amber;
      bannerIcon = Icons.podcasts;
    } else if (_repeatCount > 0) {
      bannerColor = SonicTheme.teal;
      bannerIcon = Icons.check_circle_outline;
    } else {
      bannerColor = SonicTheme.textMuted;
      bannerIcon = Icons.radio_button_unchecked;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bannerColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(bannerIcon, color: bannerColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: bannerColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Live Stats ─────────────────────────────────────────────────

  Widget _buildLiveStatsRow() {
    final elapsed = _totalDurationSeconds - _remainingSeconds;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SonicTheme.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatColumn('REPEATS', '$_repeatCount', SonicTheme.amber),
          Container(width: 1, height: 36, color: SonicTheme.border),
          _buildStatColumn('ELAPSED', _formatDuration(elapsed), SonicTheme.cyan),
          Container(width: 1, height: 36, color: SonicTheme.border),
          _buildStatColumn('INTERVAL', '${_selectedIntervalSeconds}s', SonicTheme.teal),
          Container(width: 1, height: 36, color: SonicTheme.border),
          _buildStatColumn(
            'STATUS',
            _isCurrentlyTransmitting ? 'TX' : 'WAIT',
            _isCurrentlyTransmitting ? SonicTheme.coral : SonicTheme.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color accent) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: SonicTheme.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
            color: accent,
          ),
        ),
      ],
    );
  }

  // ─── TX Progress ────────────────────────────────────────────────

  Widget _buildTxProgressBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SonicTheme.cyan.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CURRENT TRANSMISSION',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: SonicTheme.textMuted,
                ),
              ),
              Text(
                '${(_txProgress * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  color: SonicTheme.cyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _txProgress,
              backgroundColor: SonicTheme.surfaceElevated,
              color: SonicTheme.cyan,
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Message Input ──────────────────────────────────────────────

  Widget _buildMessageInputCard() {
    final byteCount = _textController.text.codeUnits.length;
    return Container(
      padding: const EdgeInsets.all(16),
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
              const Text(
                'BROADCAST MESSAGE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: SonicTheme.textMuted,
                ),
              ),
              Text(
                '$byteCount Bytes',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: SonicTheme.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _textController,
            maxLines: 2,
            maxLength: 128,
            style: const TextStyle(
              fontSize: 15,
              color: SonicTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              hintText: 'Enter message to auto-broadcast...',
              counterStyle: TextStyle(color: SonicTheme.textMuted),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  // ─── Duration Selector ──────────────────────────────────────────

  Widget _buildDurationSelector() {
    final isCustom = _durationPresets[_selectedDurationIndex].seconds == -1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.timer, size: 14, color: SonicTheme.amber),
              SizedBox(width: 6),
              Text(
                'BROADCAST DURATION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: SonicTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(_durationPresets.length, (i) {
              final isSelected = _selectedDurationIndex == i;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i > 0 ? 6 : 0),
                  child: InkWell(
                    onTap: () => setState(() => _selectedDurationIndex = i),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? SonicTheme.amber.withValues(alpha: 0.15)
                            : SonicTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? SonicTheme.amber : SonicTheme.border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _durationPresets[i].label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                            color: isSelected ? SonicTheme.amber : SonicTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          if (isCustom) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  _formatDuration(_customDurationSeconds),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    color: SonicTheme.amber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: SonicTheme.amber,
                      inactiveTrackColor: SonicTheme.surfaceElevated,
                      thumbColor: SonicTheme.amber,
                      overlayColor: SonicTheme.amber.withValues(alpha: 0.2),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _customDurationSeconds.toDouble(),
                      min: 10,
                      max: 600,
                      divisions: 59,
                      onChanged: (v) => setState(() => _customDurationSeconds = v.toInt()),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── Interval Selector ──────────────────────────────────────────

  Widget _buildIntervalSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.replay, size: 14, color: SonicTheme.cyan),
              SizedBox(width: 6),
              Text(
                'RETRANSMIT INTERVAL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: SonicTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: _intervalPresets.map((interval) {
              final isSelected = _selectedIntervalSeconds == interval;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: interval == _intervalPresets.first ? 0 : 6,
                  ),
                  child: InkWell(
                    onTap: () => setState(() => _selectedIntervalSeconds = interval),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? SonicTheme.cyan.withValues(alpha: 0.15)
                            : SonicTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? SonicTheme.cyan : SonicTheme.border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${interval}s',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                            color: isSelected ? SonicTheme.cyan : SonicTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text(
            'Message will be re-broadcast every ${_selectedIntervalSeconds}s after each transmission completes',
            style: const TextStyle(
              fontSize: 10,
              color: SonicTheme.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Redundancy ─────────────────────────────────────────────────

  Widget _buildRedundancySelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.shield_outlined, size: 14, color: SonicTheme.teal),
              SizedBox(width: 6),
              Text(
                'PER-BURST REDUNDANCY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: SonicTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildRepOption(1, '1x Std'),
              const SizedBox(width: 6),
              _buildRepOption(2, '2x ARQ'),
              const SizedBox(width: 6),
              _buildRepOption(3, '3x Max'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRepOption(int count, String label) {
    final isSelected = _repetitions == count;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _repetitions = count),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? SonicTheme.teal.withValues(alpha: 0.15)
                : SonicTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? SonicTheme.teal : SonicTheme.border,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? SonicTheme.teal : SonicTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Quick Presets ──────────────────────────────────────────────

  Widget _buildQuickPresets() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUICK DISPATCH PRESETS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: SonicTheme.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickMessages.map((msg) {
            final isSelected = _textController.text == msg;
            return ChoiceChip(
              label: Text(
                msg,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.black : SonicTheme.textPrimary,
                ),
              ),
              selected: isSelected,
              selectedColor: SonicTheme.amber,
              backgroundColor: SonicTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isSelected ? SonicTheme.amber : SonicTheme.border,
                ),
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() => _textController.text = msg);
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── Action Button ──────────────────────────────────────────────

  Widget _buildActionButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isBroadcasting
            ? () => _stopPersistentBroadcast()
            : _startPersistentBroadcast,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isBroadcasting ? SonicTheme.coral : SonicTheme.amber,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: _isBroadcasting ? 4 : 2,
        ),
        icon: Icon(
          _isBroadcasting ? Icons.stop_circle : Icons.play_circle_fill,
          size: 22,
        ),
        label: Text(
          _isBroadcasting ? 'STOP BROADCAST' : 'START PERSISTENT BROADCAST',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Duration preset model
// ═══════════════════════════════════════════════════════════════════

class _DurationPreset {
  final String label;
  final int seconds; // -1 = custom

  const _DurationPreset({required this.label, required this.seconds});
}

// ═══════════════════════════════════════════════════════════════════
// Animated pulse ring painter
// ═══════════════════════════════════════════════════════════════════

class _PulseRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _PulseRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (int i = 0; i < 3; i++) {
      final p = (progress + i / 3.0) % 1.0;
      final radius = 70 + p * 20;
      final opacity = (1.0 - p) * 0.25;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
