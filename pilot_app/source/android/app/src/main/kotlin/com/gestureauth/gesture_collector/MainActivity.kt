package com.gestureauth.gesture_collector

import android.os.Build
import android.view.InputDevice
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * 通过原生层直接读取 MotionEvent 的原始压力/接触面积，用于判断
 * "压力恒为 1.0" 是硬件不支持还是 Flutter 层丢失。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "gesture_collector/diagnostics"
    private val rawSamples = mutableListOf<JSONObject>()
    private val pending = mutableListOf<JSONObject>()

    /** JSONObject 不接受 NaN/Infinity；部分设备的触摸轴会返回这些值。 */
    private fun safe(v: Float): Double = if (v.isFinite()) v.toDouble() else 0.0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capabilities" -> result.success(
                        try {
                            capabilities()
                        } catch (_: Exception) {
                            "{}"
                        }
                    )
                    "rawSamples" -> result.success(
                        JSONObject()
                            .put("count", rawSamples.size)
                            .put("samples", JSONArray(rawSamples))
                            .toString()
                    )
                    "clear" -> {
                        rawSamples.clear()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        try {
            recordTouch(ev)
        } catch (_: Exception) {
            // 诊断代码绝不能影响正常采集。
        }
        return super.dispatchTouchEvent(ev)
    }

    private fun recordTouch(ev: MotionEvent) {
        if (ev.actionMasked == MotionEvent.ACTION_DOWN) {
            pending.clear()
        }
        if (pending.size < 8000 && ev.pointerCount > 0) {
            pending.add(
                JSONObject()
                    .put("t", ev.eventTime)
                    .put("action", ev.actionMasked)
                    .put("p", safe(ev.getPressure(0)))
                    .put("axis_p", safe(ev.getAxisValue(MotionEvent.AXIS_PRESSURE, 0)))
                    .put("hist", ev.historySize)
                    .put("src", ev.source)
                    .put("dev", ev.deviceId)
            )
            for (h in 0 until ev.historySize) {
                pending.add(
                    JSONObject()
                        .put("t", ev.getHistoricalEventTime(h))
                        .put("action", -1)
                        .put("p", safe(ev.getHistoricalPressure(h, 0)))
                        .put("hist", 0)
                        .put("src", ev.source)
                        .put("dev", ev.deviceId)
                )
            }
        }
        if (ev.actionMasked == MotionEvent.ACTION_UP ||
            ev.actionMasked == MotionEvent.ACTION_CANCEL
        ) {
            // 只保留真正的"画笔画"，忽略按钮点击这类短触摸
            if (pending.size >= 20) {
                rawSamples.clear()
                rawSamples.addAll(pending)
            }
            pending.clear()
        }
    }

    private fun capabilities(): String {
        val devices = JSONArray()
        for (id in InputDevice.getDeviceIds()) {
            val d = InputDevice.getDevice(id) ?: continue
            val sources = d.sources
            val touchscreen =
                sources and InputDevice.SOURCE_TOUCHSCREEN == InputDevice.SOURCE_TOUCHSCREEN
            val stylus = sources and InputDevice.SOURCE_STYLUS == InputDevice.SOURCE_STYLUS
            if (!touchscreen && !stylus) continue
            val axes = JSONObject()
            for (range in d.motionRanges) {
                if (range.axis == MotionEvent.AXIS_SIZE ||
                    range.axis == MotionEvent.AXIS_TOUCH_MAJOR ||
                    range.axis == MotionEvent.AXIS_TOUCH_MINOR
                ) {
                    continue
                }
                axes.put(
                    MotionEvent.axisToString(range.axis),
                    JSONObject()
                        .put("min", safe(range.min))
                        .put("max", safe(range.max))
                        .put("resolution", safe(range.resolution))
                )
            }
            devices.put(
                JSONObject()
                    .put("id", id)
                    .put("name", d.name)
                    .put("sources", Integer.toHexString(sources))
                    .put("touchscreen", touchscreen)
                    .put("stylus", stylus)
                    .put("axes", axes)
            )
        }
        return JSONObject()
            .put("manufacturer", Build.MANUFACTURER)
            .put("model", Build.MODEL)
            .put("sdk", Build.VERSION.SDK_INT)
            .put("devices", devices)
            .toString()
    }
}
