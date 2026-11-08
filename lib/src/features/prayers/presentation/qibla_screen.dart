import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../prayer/domain/models/selected_city.dart';
import '../../quran/presentation/utils/quran_ui_utils.dart';
import 'controllers/prayers_controller.dart';

/// Kaaba coordinates (Masjid al-Haram).
const double kKaabaLatitude = 21.422487;
const double kKaabaLongitude = 39.826206;

/// Initial great-circle bearing from (lat, lng) to the Kaaba, in degrees
/// clockwise from true north (0..360).
double qiblaBearing(double latitude, double longitude) {
  double rad(double d) => d * math.pi / 180;
  final phi1 = rad(latitude);
  final phi2 = rad(kKaabaLatitude);
  final dLambda = rad(kKaabaLongitude - longitude);
  final y = math.sin(dLambda) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
  final deg = math.atan2(y, x) * 180 / math.pi;
  return (deg + 360) % 360;
}

/// Great-circle distance to the Kaaba in kilometres.
double distanceToKaabaKm(double latitude, double longitude) {
  double rad(double d) => d * math.pi / 180;
  const r = 6371.0;
  final dPhi = rad(kKaabaLatitude - latitude);
  final dLambda = rad(kKaabaLongitude - longitude);
  final a = math.pow(math.sin(dPhi / 2), 2) +
      math.cos(rad(latitude)) *
          math.cos(rad(kKaabaLatitude)) *
          math.pow(math.sin(dLambda / 2), 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

class QiblaScreen extends ConsumerWidget {
  const QiblaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cityAsync = ref.watch(selectedPrayerCityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('اتجاه القبلة')),
      body: SafeArea(
        child: cityAsync.when(
          data: (city) => _QiblaBody(city: city),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'اختر مدينتك أولاً من شاشة الصلاة لحساب اتجاه القبلة.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QiblaBody extends StatefulWidget {
  final SelectedCity city;
  const _QiblaBody({required this.city});

  @override
  State<_QiblaBody> createState() => _QiblaBodyState();
}

class _QiblaBodyState extends State<_QiblaBody> {
  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<AccelerometerEvent>? _accSub;
  List<double>? _gravity;
  double? _heading; // degrees clockwise from magnetic north
  bool _sensorError = false;

  @override
  void initState() {
    super.initState();
    try {
      _accSub = accelerometerEventStream().listen(
        (e) => _gravity = [e.x, e.y, e.z],
        onError: (Object _) => _markError(),
        cancelOnError: true,
      );
      _magSub = magnetometerEventStream().listen(
        _onMagnetometer,
        onError: (Object _) => _markError(),
        cancelOnError: true,
      );
    } catch (_) {
      _sensorError = true;
    }
  }

  void _markError() {
    if (mounted) setState(() => _sensorError = true);
  }

  /// Tilt-compensated heading using the gravity vector (Android rotation
  /// matrix method), low-pass filtered to keep the needle steady.
  void _onMagnetometer(MagnetometerEvent m) {
    final g = _gravity;
    if (g == null) return;
    final ax = g[0], ay = g[1], az = g[2];
    final ex = m.x, ey = m.y, ez = m.z;
    var hx = ey * az - ez * ay;
    var hy = ez * ax - ex * az;
    final hz = ex * ay - ey * ax;
    final normH = math.sqrt(hx * hx + hy * hy + hz * hz);
    if (normH < 0.1) return;
    hx /= normH;
    hy /= normH;
    final normA = math.sqrt(ax * ax + ay * ay + az * az);
    if (normA == 0) return;
    final my = (az * hx - ax * (hz / normH)) / normA;
    final azimuth = math.atan2(hy, my) * 180 / math.pi;
    final heading = (azimuth + 360) % 360;

    final prev = _heading;
    double next;
    if (prev == null) {
      next = heading;
    } else {
      var delta = heading - prev;
      if (delta > 180) delta -= 360;
      if (delta < -180) delta += 360;
      next = (prev + delta * 0.15 + 360) % 360;
    }
    if (mounted) setState(() => _heading = next);
  }

  @override
  void dispose() {
    _magSub?.cancel();
    _accSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final city = widget.city;
    final bearing = qiblaBearing(city.latitude, city.longitude);
    final distance = distanceToKaabaKm(city.latitude, city.longitude);
    final heading = _heading;
    final relative = heading == null ? bearing : (bearing - heading + 360) % 360;
    final aligned = heading != null && (relative < 4 || relative > 356);
    final accent = isDark ? AppColors.darkGoldAccent : AppColors.goldDark;
    final primary = isDark ? AppColors.darkForestPrimary : AppColors.forestPrimary;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          city.arabicName ?? city.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'القبلة على ${QuranUiUtils.toArabicDigits(bearing.round())}° من الشمال · '
          'المسافة إلى مكة ${QuranUiUtils.toArabicDigits(distance.round())} كم',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 28),
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, c) {
              final size = c.maxWidth;
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Dial rotates so that "N" points to real north.
                  Transform.rotate(
                    angle: -(heading ?? 0) * math.pi / 180,
                    child: CustomPaint(
                      size: Size.square(size),
                      painter: _DialPainter(
                        ring: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
                        face: isDark ? AppColors.darkSurface : AppColors.cardSurface,
                        tick: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                        north: accent,
                      ),
                    ),
                  ),
                  // Qibla needle (relative to the phone's top).
                  Transform.rotate(
                    angle: relative * math.pi / 180,
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.only(top: size * 0.08),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mosque_rounded,
                                  size: size * 0.11,
                                  color: aligned ? primary : accent),
                              Container(
                                width: 4,
                                height: size * 0.3,
                                decoration: BoxDecoration(
                                  color: aligned ? primary : accent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: aligned
                ? (isDark ? AppColors.darkSurfaceHigh : AppColors.forestSoftTint)
                : (isDark ? AppColors.darkSurface : AppColors.goldSoftTint),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: Text(
            _sensorError
                ? 'البوصلة غير متاحة على هذا الجهاز. استخدم الزاوية المكتوبة أعلاه مع بوصلة خارجية.'
                : heading == null
                    ? 'جارٍ تشغيل البوصلة… أمسك الهاتف بشكل أفقي.'
                    : aligned
                        ? 'أنت متجه نحو القبلة ✓'
                        : 'لِف الهاتف حتى يشير السهم لأعلى.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: AppTheme.uiFont, fontFamilyFallback: AppTheme.uiFontFallback, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'لدقة أفضل: ابعد عن المعادن والأجهزة الكهربائية، وحرّك الهاتف على شكل ٨ لمعايرة البوصلة.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _DialPainter extends CustomPainter {
  final Color ring;
  final Color face;
  final Color tick;
  final Color north;

  _DialPainter({
    required this.ring,
    required this.face,
    required this.tick,
    required this.north,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    canvas.drawCircle(c, r, Paint()..color = face);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    for (var i = 0; i < 72; i++) {
      final a = i * 5 * math.pi / 180;
      final major = i % 18 == 0;
      final len = major ? 16.0 : (i % 6 == 0 ? 10.0 : 5.0);
      final p1 = c + Offset(math.sin(a), -math.cos(a)) * (r - 6);
      final p2 = c + Offset(math.sin(a), -math.cos(a)) * (r - 6 - len);
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = i == 0 ? north : tick
          ..strokeWidth = major ? 3 : 1.4,
      );
    }
    const labels = ['ش', 'ق', 'ج', 'غ'];
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontFamily: AppTheme.uiFont,
            fontFamilyFallback: AppTheme.uiFontFallback,
            color: i == 0 ? north : tick,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      final pos = c + Offset(math.sin(a), -math.cos(a)) * (r - 40);
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.ring != ring || old.face != face || old.tick != tick || old.north != north;
}
