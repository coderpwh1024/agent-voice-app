# Agent Voice App

`agent-service-toolkit` 的独立 Flutter 实时语音客户端。工程按后端协议版本 `1` 实现，不持有百炼 Key，也不会把后端 `AUTH_SECRET` 固定在安装包中。

## 当前能力

- 读取 `/voice/capabilities`，选择 Agent 与服务端配置的音色，并展示音色名称与描述
- 邮箱验证码登录与自动注册，接入 `/auth/email/code`、`/auth/email/verify`
- 登录态安全保存：iOS Keychain、Android Keystore AES-GCM
- 获取与编辑个人资料，接入 `/users/me`，支持昵称和头像上传
- 创建、关闭语音会话，并用 Bearer Token 建立 WebSocket
- 按后端契约编码/解码 45 字节 `VCE1` PCM 帧头
- 上行 16 kHz PCM16 mono；下行 24 kHz PCM16 mono
- 实时字幕、流式回答、文字调试输入、工具状态协议兼容
- 本地立即停播、`response.cancel`、旧回答音频/文本隔离
- `input.speech_hint` 插话提示及 `playback.resume`
- 原生端确认已播放的 segment/response，再上报播放进度
- LangGraph `approval.required` 的同意/拒绝入口
- 用户线程列表与历史记录恢复
- Android `VOICE_COMMUNICATION`、`AcousticEchoCanceler`、`NoiseSuppressor`
- iOS `AVAudioSession.voiceChat`、Voice Processing 与系统音频转换
- sherpa-onnx 离线中文唤醒词“小美”，带 1.2 秒前滚音频
- 唤醒后的百炼 ASR 二次确认，误唤醒自动关闭并返回待机
- 本地能量 VAD 自动插话，以及 AEC、降噪、音量和削波质量上报

唤醒目前是 App 前台待机能力：进入首页后默认启动“小美”离线关键词检测，命中后才建立网络语音会话，无需手动打开开关。应用进入系统挂起状态或被用户结束后不承诺继续唤醒；Android 后台前台服务与 iOS 后台录音需要单独的产品权限和上架策略。AEC、蓝牙/来电切换、误唤醒率和插话效果仍必须在目标真机上验收。

## 后端准备

后端位于相邻目录：

```text
/Users/coderpwh/python/workspace/
├── agent-service-toolkit/
└── agent-voice-app/
```

后端至少需要配置 PostgreSQL、Redis、SMTP、`DASHSCOPE_API_KEY`、`AUTH_SECRET`、`APP_TOKEN_SECRET`、`EMAIL_AUTH_ENABLED=true` 和 `VOICE_ENABLED=true`。详细说明见后端的 `docs/Voice_API.md` 与 `docs/Accounts_and_Credentials.md`。

App 启动后输入邮箱即可登录。新邮箱首次验证成功时由后端自动注册，已有邮箱则直接登录；两种流程都会返回用户绑定的短期 App Token。App 不会保存 `AUTH_SECRET` 或 `APP_TOKEN_SECRET`。

音色列表由后端 `voice_options` 下发，App 不内置供应商音色。新版接口会显示中文名称、音色 ID 和描述；旧版接口只有 `voices` 字符串数组时仍可正常选择。音色在创建语音会话时生效，当前协议不支持会话中热切换，需要先结束会话再选择其他音色重新开始。

兼容的可信后台仍可签发开发 Token：

```http
POST /auth/token
Authorization: Bearer <AUTH_SECRET>
Content-Type: application/json

{"user_id":"user-123"}
```

`AUTH_SECRET` 只能由可信服务使用，不能填入 App。通过 Dart Define 注入的开发 Token 仅用于调试；正常用户应使用邮箱验证码入口。

## 运行

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

也可在开发期用 Dart Define 设置初值：

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

USB 真机调试使用项目脚本。它会构建带 `http://127.0.0.1:8000` 地址的 Debug APK、覆盖安装、重新建立 `adb reverse` 并启动 App：

```bash
./scripts/install_usb_debug.sh
```

连接多个设备时，将目标设备序列号作为第一个参数。后端使用其他端口时可传入 `BACKEND_PORT`：

```bash
BACKEND_PORT=8080 ./scripts/install_usb_debug.sh 20b2a515
```

地址说明：

- Android 模拟器访问宿主机使用 `http://10.0.2.2:8000`
- USB 真机使用安装脚本映射到 `http://127.0.0.1:8000`；USB 重连后需重新执行脚本或 `adb reverse tcp:8000 tcp:8000`
- 非 USB 真机使用电脑的局域网地址，后端需监听可达网卡
- iOS 模拟器可用 `http://127.0.0.1:8000`
- 生产环境必须使用 HTTPS/WSS

Android Manifest 当前允许明文 HTTP，仅用于本地开发。发布前应关闭 `android:usesCleartextTraffic`，并配置可信 HTTPS/WSS 域名。登录 Token 不写入普通偏好存储：iOS 使用 Keychain，Android 使用 Keystore 内的 AES-GCM 密钥加密后再持久化。退出登录会删除本地会话。

## 工程结构

```text
lib/
├── core/api/                  HTTP、WebSocket、DTO、二进制协议
├── core/auth/                 登录态安全存储
├── core/audio/                Flutter 原生音频桥与 sherpa-onnx 唤醒引擎
├── core/config/               运行配置
├── features/auth/             登录、注册与邮箱验证码页面
├── features/voice_session/    会话状态、打断、播放确认、主界面
├── features/conversations/    历史会话
└── features/settings/         后端与身份设置
android/                       AudioRecord / AudioTrack / Android AEC
ios/                           AVAudioEngine / Voice Processing
test/                          协议契约与 Widget 测试
```

麦克风只有一条采集链路。Android 每 40 ms 发送一块 PCM；iOS 在原生音频线程完成硬件采样率到 16 kHz 的转换。待机音频送入独立 isolate 中的 sherpa-onnx，不上传；进入会话后才发送给后端。模型来源、许可和校验值见 `assets/models/sherpa_kws/MODEL_SOURCE.md`。

## 构建与验证

```bash
flutter analyze
flutter test
flutter build apk --debug
```

本仓库当前环境的 APK 位于 `build/app/outputs/flutter-apk/app-debug.apk`。

iOS 首次构建前需要完成本机 Xcode 初始化：

```bash
sudo xcodebuild -license
sudo xcodebuild -runFirstLaunch
flutter build ios --debug --no-codesign
```

真机至少验证：外放时识别人声、停止后 200 ms 内静音、连续插话不恢复旧音频、断网重连、耳机/蓝牙切换、来电中断、30 分钟/50 轮资源回收。App 已实现协议与端侧隔离机制，但这些硬件指标不能由模拟器或单元测试替代。
