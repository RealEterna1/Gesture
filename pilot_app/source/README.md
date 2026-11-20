# 手势采集（gesture_collector）

毕业设计的触屏手势认证数据采集 App：逐笔记录触摸轨迹的**坐标、事件时间戳、压力、接触面积**，
用于验证「速度 / 压力能否被准确采集」，并作为后续相似度认证模型的数据来源。

## 功能

- 多笔手势采集，每笔单独记录（含笔序、笔间停顿）
- 每个采样点记录：相对时间 `t`、系统事件时间戳 `raw_us`、`x/y`、压力 `p`（含 `p_min`/`p_max`）、接触面积 `size`、`tilt`
- 实时压力曲线 + 采样率/笔画数显示，便于现场判断压力是否为真实变化
- 每次保存后弹出统计：笔画数、点数、时长、采样率、压力范围/标准差/不同取值数、接触面积、平均速度
- 数据质量问题（压力恒定、采样率过低、多指触摸、笔画被取消）自动告警
- 样本以 JSON 保存在应用私有目录，可单条分享或一次性导出全部

## 构建

本机 SDK 安装在 `D:\Gesture\.android-sdk`（不入库），构建时需显式指定：

```powershell
$env:ANDROID_HOME="D:\Gesture\.android-sdk"
$env:ANDROID_SDK_ROOT="D:\Gesture\.android-sdk"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.googleapis.com"
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`（已复制到 `../dist/gesture_collector-1.0.0.apk`）。

## 安装

1. 手机打开「开发者选项 → USB 调试」，数据线连接电脑
2. `D:\Gesture\.android-sdk\platform-tools\adb.exe install -r D:\Gesture\dist\gesture_collector-1.0.0.apk`
3. 或直接把 APK 传到手机点击安装（需允许安装未知来源应用）

## 数据说明

样本字段见 `lib/models.dart`，导出文件为：

```json
{
  "exported_at": "...",
  "sample_count": 20,
  "samples": [ { "schema": "gesture-sample-v1", "subject_id": "P01", "...": "..." } ]
}
```

关键字段：`strokes[].points[]` 为原始点序列，`stats` 为现场统计，`device` / `canvas`
记录机型、系统版本、画布尺寸、像素比与刷新率。

## 注意

- 采样率取决于设备触摸上报频率，App 显示的是实测值
- Flutter 未暴露 Android 的 historical points（同一 MotionEvent 内的批量采样），如需传感器级采样需写原生插件
- `path_provider_android` 固定在 2.2.x：2.3.x 的 jni/CMake 实现会在只读 pub 缓存中写构建产物而导致构建失败
