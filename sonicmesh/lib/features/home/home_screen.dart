import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/routes.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopHeader(),
              const SizedBox(height: 24),
              _buildRadarHero(),
              const SizedBox(height: 24),
              _buildNetworkStatusCard(),
              const SizedBox(height: 24),
              _buildSectionTitle('OPERATIONS'),
              const SizedBox(height: 12),
              _buildActionCard(
                title: 'BROADCAST CONSOLE',
                subtitle: 'Transmit packets via continuous-phase acoustic FSK',
                icon: Icons.cell_tower,
                accentColor: SonicTheme.cyan,
                onTap: () => Navigator.pushNamed(context, Routes.broadcast),
              ),
              const SizedBox(height: 14),
              _buildActionCard(
                title: 'RECEIVER CONSOLE',
                subtitle: 'Microphone signal demodulator & real-time packet sniffer',
                icon: Icons.hearing,
                accentColor: SonicTheme.teal,
                onTap: () => Navigator.pushNamed(context, Routes.receiver),
              ),
              const SizedBox(height: 14),
              _buildActionCard(
                title: 'DSP DIAGNOSTICS',
                subtitle: 'In-memory loopback verification & audio telemetry',
                icon: Icons.analytics_outlined,
                accentColor: SonicTheme.amber,
                onTap: () => Navigator.pushNamed(context, Routes.diagnostics),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SonicTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SonicTheme.cyan.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.waves, color: SonicTheme.cyan, size: 26),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'SONICMESH',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color: SonicTheme.textPrimary,
                  ),
                ),
                Text(
                  'ACOUSTIC MESH NETWORK',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: SonicTheme.teal,
                  ),
                ),
              ],
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: SonicTheme.teal.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: SonicTheme.teal.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.circle, color: SonicTheme.teal, size: 8),
              SizedBox(width: 6),
              Text(
                'AIR-GAP',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: SonicTheme.teal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRadarHero() {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: List.generate(3, (index) {
                  final progress = (_pulseController.value + (index / 3.0)) % 1.0;
                  final radius = 30.0 + progress * 70.0;
                  final opacity = (1.0 - progress) * 0.4;
                  return Container(
                    width: radius * 2,
                    height: radius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: SonicTheme.cyan.withValues(alpha: opacity),
                        width: 1.5,
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SonicTheme.surfaceElevated,
              boxShadow: [
                BoxShadow(
                  color: SonicTheme.cyan.withValues(alpha: 0.3),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
              border: Border.all(color: SonicTheme.cyan, width: 2),
            ),
            child: const Icon(Icons.volume_up, color: SonicTheme.cyan, size: 30),
          ),
          const Positioned(
            bottom: 14,
            child: Text(
              '16.5 kHz / 17.5 kHz CPFSK READY',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: SonicTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SonicTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('PHYSICAL PHY', 'Speaker / Mic', SonicTheme.cyan),
          Container(width: 1, height: 32, color: SonicTheme.border),
          _buildStatItem('MODULATION', '2-FSK 25 Baud', SonicTheme.teal),
          Container(width: 1, height: 32, color: SonicTheme.border),
          _buildStatItem('INTEGRITY', 'CRC-32 IEEE', SonicTheme.amber),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color accent) {
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
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: SonicTheme.textMuted,
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: accentColor.withValues(alpha: 0.1),
        highlightColor: accentColor.withValues(alpha: 0.05),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: SonicTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SonicTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: SonicTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SonicTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: SonicTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
