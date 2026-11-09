package dev.zadalruh.zad_alruh.qibla

import android.app.Activity
import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.view.Surface
import io.flutter.plugin.common.EventChannel

/**
 * Streams the device heading (degrees clockwise from TRUE north) for the Qibla
 * screen. Uses the fused rotation-vector sensor (accelerometer + magnetometer
 * + gyroscope) which is far steadier than raw magnetometer math, corrects for
 * screen rotation, and adds the local magnetic declination.
 *
 * Events: {"heading": Double, "accuracy": Int (0..3)}.
 * Error code "no_sensor" when the device has no compass.
 */
class CompassStreamHandler(private val activity: Activity) :
    EventChannel.StreamHandler, SensorEventListener {

    private val sensorManager =
        activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var sink: EventChannel.EventSink? = null
    private var declination = 0f
    private var accuracy = SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM
    private var lastEmit = 0L
    private val rotation = FloatArray(9)
    private val remapped = FloatArray(9)
    private val orientation = FloatArray(3)

    // Fallback (no rotation vector): accelerometer + magnetometer.
    private var gravity: FloatArray? = null
    private var geomagnetic: FloatArray? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        val args = arguments as? Map<*, *>
        val lat = (args?.get("lat") as? Number)?.toFloat()
        val lng = (args?.get("lng") as? Number)?.toFloat()
        if (lat != null && lng != null) {
            declination = GeomagneticField(lat, lng, 0f, System.currentTimeMillis()).declination
        }

        val rotationVector = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (rotationVector != null) {
            sensorManager.registerListener(this, rotationVector, SensorManager.SENSOR_DELAY_GAME)
            // Magnetometer accuracy drives the "calibrate" hint.
            sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)?.let {
                sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
            }
            return
        }
        val acc = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        val mag = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
        if (acc == null || mag == null) {
            events.error("no_sensor", "No compass sensor on this device", null)
            sink = null
            return
        }
        sensorManager.registerListener(this, acc, SensorManager.SENSOR_DELAY_GAME)
        sensorManager.registerListener(this, mag, SensorManager.SENSOR_DELAY_GAME)
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        sink = null
        gravity = null
        geomagnetic = null
    }

    override fun onAccuracyChanged(sensor: Sensor?, newAccuracy: Int) {
        if (sensor?.type == Sensor.TYPE_MAGNETIC_FIELD) accuracy = newAccuracy
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> {
                SensorManager.getRotationMatrixFromVector(rotation, event.values)
                emitFromRotation()
            }
            Sensor.TYPE_ACCELEROMETER -> {
                gravity = event.values.clone()
                computeFallback()
            }
            Sensor.TYPE_MAGNETIC_FIELD -> {
                accuracy = event.accuracy
                if (sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) == null) {
                    geomagnetic = event.values.clone()
                    computeFallback()
                }
            }
        }
    }

    private fun computeFallback() {
        val g = gravity ?: return
        val m = geomagnetic ?: return
        if (SensorManager.getRotationMatrix(rotation, null, g, m)) emitFromRotation()
    }

    private fun emitFromRotation() {
        val now = System.currentTimeMillis()
        if (now - lastEmit < 50) return
        lastEmit = now

        @Suppress("DEPRECATION")
        val displayRotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation ?: Surface.ROTATION_0
        } else {
            activity.windowManager.defaultDisplay.rotation
        }
        val (axisX, axisY) = when (displayRotation) {
            Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
            Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
            Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
            else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
        }
        SensorManager.remapCoordinateSystem(rotation, axisX, axisY, remapped)
        SensorManager.getOrientation(remapped, orientation)
        val magnetic = Math.toDegrees(orientation[0].toDouble())
        val trueHeading = ((magnetic + declination) % 360 + 360) % 360
        sink?.success(mapOf("heading" to trueHeading, "accuracy" to accuracy))
    }
}
