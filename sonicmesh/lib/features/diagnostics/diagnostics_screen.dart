import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../native/acoustic_channel.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _isRunningTest = false;
  Map<String, dynamic>? _loopbackResult;
  Map<String, dynamic>? _diagnosticsData;

  @override
  void initState() {
    super.initState();
    _fetchDiagnostics();
  }

  Future<void> _fetchDiagnostics() async {
    final diag = await AcousticChannel.instance.getDiagnostics();
    if (mounted) {
      setState(() {
        _diagnosticsData = diag;
      });
    }
  }

  Future<void> _runLoopbackTest() async {
    setState(() {
      _isRunningTest = true;
      _loopbackResult = null;
    });

    final res = await AcousticChannel.instance.runLoopbackTest('SonicMesh Acoustic Air-Gap Loopback Test 001');

    if (mounted) {
      setState(() {
        _isRunningTest = false;
        _loopbackResult = res;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DSP & AIR-GAP DIAGNOSTICS'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAirGapComplianceCard(),
              const SizedBox(height: 20),
              _buildLoopbackTestCard(),
              const SizedBox(height: 20),
              _buildPhyConfigCard(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAirGapComplianceCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SonicTheme.teal.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: SonicTheme.teal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shield_outlined, color: SonicTheme.teal, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'INFRASTRUCTURE-FREE POLICY',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: SonicTheme.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildPolicyRow('Wi-Fi Required', 'NO (100% Offline)', Icons.wifi_off),
          const SizedBox(height: 8),
          _buildPolicyRow('Bluetooth Required', 'NO (100% Offline)', Icons.bluetooth_disabled),
          const SizedBox(height: 8),
          _buildPolicyRow('Cellular Data', 'NO (100% Offline)', Icons.signal_cellular_off),
          const SizedBox(height: 8),
          _buildPolicyRow('Internet / Cloud', 'NO (Pure Air P2P)', Icons.cloud_off),
        ],
      ),
    );
  }

  Widget _buildPolicyRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: SonicTheme.teal),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: SonicTheme.textSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
            color: SonicTheme.teal,
          ),
        ),
      ],
    );
  }

  Widget _buildLoopbackTestCard() {
    final success = _loopbackResult?['success'] as bool? ?? false;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'IN-MEMORY DSP LOOPBACK TEST',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: SonicTheme.textMuted,
                ),
              ),
              if (_loopbackResult != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (success ? SonicTheme.teal : SonicTheme.coral).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    success ? 'PASSED' : 'FAILED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: success ? SonicTheme.teal : SonicTheme.coral,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Tests native Kotlin Encode → CPFSK Modulate → Goertzel Demodulate → CRC32 Decode pipeline entirely in memory.',
            style: TextStyle(fontSize: 12, color: SonicTheme.textSecondary),
          ),
          if (_loopbackResult != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SonicTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SonicTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildResultRow('Original:', _loopbackResult!['original']?.toString() ?? ''),
                  const SizedBox(height: 6),
                  _buildResultRow('Decoded:', _loopbackResult!['decoded']?.toString() ?? '', isSuccess: success),
                  const Divider(color: SonicTheme.border, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMetric('EXEC TIME', '${_loopbackResult!['elapsedMs']} ms'),
                      _buildMetric('SAMPLES', '${_loopbackResult!['pcmSamples']}'),
                      _buildMetric('RATE', '${_loopbackResult!['baud']} Baud'),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isRunningTest ? null : _runLoopbackTest,
              style: ElevatedButton.styleFrom(
                backgroundColor: SonicTheme.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isRunningTest
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.play_arrow, size: 20),
              label: Text(
                _isRunningTest ? 'TESTING DSP PIPELINE...' : 'RUN DSP LOOPBACK TEST',
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, String value, {bool? isSuccess}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: SonicTheme.textMuted, fontFamily: 'monospace'),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: isSuccess == null
                  ? SonicTheme.textPrimary
                  : (isSuccess ? SonicTheme.teal : SonicTheme.coral),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: SonicTheme.textMuted, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: SonicTheme.cyan)),
      ],
    );
  }

  Widget _buildPhyConfigCard() {
    final sRate = _diagnosticsData?['sampleRate']?.toString() ?? '44,100';
    final f0 = _diagnosticsData?['f0']?.toString() ?? '16,500';
    final f1 = _diagnosticsData?['f1']?.toString() ?? '17,500';
    final dur = _diagnosticsData?['symbolDurationMs']?.toString() ?? '40';
    final baud = _diagnosticsData?['baudRate']?.toString() ?? '25';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACOUSTIC PHY PROFILE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: SonicTheme.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          _buildParamRow('Sample Rate', '$sRate Hz (PCM 16-bit Mono)'),
          _buildParamRow('Mark Frequency (0)', '$f0 Hz'),
          _buildParamRow('Space Frequency (1)', '$f1 Hz'),
          _buildParamRow('Symbol Duration', '$dur ms ($baud Baud)'),
          _buildParamRow('Preamble Sequence', '4x 0xAA (Alternating Tones)'),
          _buildParamRow('Sync Word', '0x7E (01111110)'),
          _buildParamRow('Error Detection', 'CRC-32 IEEE 802.3'),
        ],
      ),
    );
  }

  Widget _buildParamRow(String param, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(param, style: const TextStyle(fontSize: 13, color: SonicTheme.textSecondary)),
          Text(val, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: SonicTheme.cyan)),
        ],
      ),
    );
  }
}
