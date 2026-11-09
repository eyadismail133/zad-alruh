import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Signed smallest difference a-b in degrees (-180..180].
double angleDiff(double a, double b) {
  var d = (a - b) % 360;
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;
  return d;
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
                'اختر مدينتك أولاً من الإعدادات لحساب اتجاه القبلة.',
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
  static const EventChannel _compass =
      EventChannel('dev.zadalruh.zad_alruh/compass');

  StreamSubscription<dynamic>? _sub;
  double? _heading; // degrees clockwise from TRUE north (native fused sensor)
  int _accuracy = 3;
  bool _noSensor = false;
  bool _wasAligned = false;

  @override
  void initState() {
    super.initState();
    try {
      _sub = _compass.receiveBroadcastStream({
        'lat': widget.city.latitude,
        'lng': widget.city.longitude,
      }).listen(
        (dynamic e) {
          if (e is! Map) return;
          final h = (e['heading'] as num?)?.toDouble();
          if (h == null) return;
          final prev = _heading;
          // Light smoothing across the 0/360 seam.
          final next = prev == null ? h : (prev + angleDiff(h, prev) * 0.35 + 360) % 360;
          if (!mounted) return;
          setState(() {
            _heading = next;
            _accuracy = (e['accuracy'] as num?)?.toInt() ?? 3;
          });
        },
        onError: (Object _) {
          if (mounted) setState(() => _noSensor = true);
        },
      );
    } catch (_) {
      _noSensor = true;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final city = widget.city;
    final bearing = qiblaBearing(city.latitude, city.longitude);
    final distance = distanceToKaabaKm(city.latitude, city.longitude);
    final heading = _heading;

    // How far the phone must turn: positive = turn right (clockwise).
    final turn = heading == null ? null : angleDiff(bearing, heading);
    final aligned = turn != null && turn.abs() <= 5;
    if (aligned && !_wasAligned) HapticFeedback.mediumImpact();
    _wasAligned = aligned;

    final good = isDark ? AppColors.darkForestPrimary : AppColors.forestPrimary;
    final gold = isDark ? AppColors.darkGoldAccent : AppColors.goldDark;

    String status;
    if (_noSensor) {
      status = 'الموبايل ده مفيهوش بوصلة. وجّه نفسك على زاوية '
          '${QuranUiUtils.toArabicDigits(bearing.round())}° من الشمال.';
    } else if (turn == null) {
      status = 'جارٍ تشغيل البوصلة…';
    } else if (aligned) {
      status = 'أنت متجه للقبلة ✓';
    } else {
      final deg = QuranUiUtils.toArabicDigits(turn.abs().round());
      status = turn > 0 ? 'لِف يمين $deg°' : 'لِف شمال $deg°';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          city.arabicName ?? city.name,
          textAlign: TextAlign.center,
          style: text.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'القبلة ${QuranUiUtils.toArabicDigits(bearing.round())}° من الشمال · '
          '${QuranUiUtils.toArabicDigits(distance.round())} كم إلى مكة',
          textAlign: TextAlign.center,
          style: text.bodySmall,
        ),
        const SizedBox(height: 24),
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, c) {
              final size = c.maxWidth;
              final dialAngle = -(heading ?? 0) * math.pi / 180;
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Dial: N points to true north, Kaaba marker at the bearing.
                  Transform.rotate(
                    angle: dialAngle,
                    child: CustomPaint(
                      size: Size.square(size),
                      painter: _DialPainter(
                        face: isDark ? AppColors.darkSurface : AppColors.cardSurface,
                        ring: aligned ? good : (isDark ? AppColors.darkCardBorder : AppColors.cardBorder),
                        tick: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                        north: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                        kaaba: aligned ? good : gold,
                        bearing: bearing,
                      ),
                    ),
                  ),
                  // Fixed pointer = where the top of the phone points.
                  Positioned(
                    top: 0,
                    child: Icon(
                      Icons.arrow_drop_down_rounded,
                      size: size * 0.16,
                      color: aligned ? good : scheme.onSurface,
                    ),
                  ),
                  Container(
                    width: size * 0.36,
                    height: size * 0.36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: aligned
                          ? good
                          : (isDark ? AppColors.darkSurfaceHigh : AppColors.forestSoftTint),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.mosque_rounded,
                      size: size * 0.16,
                      color: aligned ? Colors.white : good,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: aligned
                ? good
                : (isDark ? AppColors.darkSurface : AppColors.goldSoftTint),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: Text(
            status,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.uiFont,
              fontFamilyFallback: AppTheme.uiFontFallback,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: aligned ? Colors.white : (isDark ? AppColors.darkTextPrimary : AppColors.textDark),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (!_noSensor && _accuracy < 2)
          Text(
            'البوصلة محتاجة معايرة: حرّك الموبايل في الهوا على شكل رقم ٨ كذا مرة.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: gold),
          )
        else
          Text(
            'امسك الموبايل مفرود قدامك وبعيد عن المعادن والمغناطيس، ولِف لحد ما العلامة الذهبية توصل للسهم اللي فوق.',
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
      ],
    );
  }
}

class _DialPainter extends CustomPainter {
  final Color face;
  final Color ring;
  final Color tick;
  final Color north;
  final Color kaaba;
  final double bearing;

  _DialPainter({
    required this.face,
    required this.ring,
    required this.tick,
    required this.north,
    required this.kaaba,
    required this.bearing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 10;
    canvas.drawCircle(c, r, Paint()..color = face);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    Offset at(double deg, double radius) {
      final a = deg * math.pi / 180;
      return c + Offset(math.sin(a), -math.cos(a)) * radius;
    }

    for (var d = 0; d < 360; d += 10) {
      final major = d % 90 == 0;
      canvas.drawLine(
        at(d.toDouble(), r - 8),
        at(d.toDouble(), r - (major ? 22 : 14)),
        Paint()
          ..color = tick.withAlpha(major ? 255 : 140)
          ..strokeWidth = major ? 3 : 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
    const labels = {0: 'ش', 90: 'ق', 180: 'ج', 270: 'غ'};
    labels.forEach((deg, label) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: AppTheme.uiFont,
            fontFamilyFallback: AppTheme.uiFontFallback,
            color: deg == 0 ? north : tick,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      final pos = at(deg.toDouble(), r - 42);
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    });

    // Kaaba marker on the rim at the qibla bearing.
    final k = at(bearing, r - 2);
    canvas.drawCircle(k, 16, Paint()..color = kaaba);
    canvas.drawRect(
      Rect.fromCenter(center: k, width: 14, height: 14),
      Paint()..color = AppColors.kaabaBlack,
    );
    canvas.drawLine(
      k + const Offset(-7, -3),
      k + const Offset(7, -3),
      Paint()
        ..color = kaaba
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.face != face ||
      old.ring != ring ||
      old.tick != tick ||
      old.north != north ||
      old.kaaba != kaaba ||
      old.bearing != bearing;
}
