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
- 最近 30 天聊天记录：按 UTC 日期归档、切换助手查询、分会话查看当天消息，以及继续历史对话
- Android `VOICE_COMMUNICATION`、`AcousticEchoCanceler`、`NoiseSuppressor`
- iOS `AVAudioSession.voiceChat`、Voice Processing 与系统音频转换
- sherpa-onnx 离线中文唤醒词“小美小美”，默认带 2.2 秒前滚音频
- 唤醒后的百炼 ASR 二次确认，误唤醒自动关闭并返回待机
- 确认唤醒后按所选音色主动播报“我在，小美随时为你服务。”；紧接问题时继续回答
- 本地能量 VAD 自动插话，以及 AEC、降噪、音量和削波质量上报

唤醒目前是 App 前台待机能力：进入首页后默认启动“小美小美”离线关键词检测，命中后才建立网络语音会话，无需手动打开开关。可连读“小美小美”，也可短暂停顿喊“小美，小美”，连续呼喊三个或更多同样兼容；单个“小美”不作为完整唤醒词。重复呼喊只建立一次连接，后端剥离全部开头呼喊，并兼容 ASR 把两声拆成两段。默认 10 秒内未确认有效唤醒则关闭会话并返回待机；确认后仅呼喊会固定应答，不调用聊天模型。

本次需要同时更新 App 与相邻 `agent-service-toolkit` 后端。后端 Nacos 配置建议使用 `voice.wake.word: 小美小美`、`pre_roll_ms: 2200`，可通过 `greeting` 自定义应答和 `confirm_seconds` 调整确认超时。旧的 `word: 小美` 自动归一为双声唤醒；已显式配置的前滚长度仍以配置值为准。

应用进入系统挂起状态或被用户结束后不承诺继续唤醒；Android 后台前台服务与 iOS 后台录音需要单独的产品权限和上架策略。AEC、蓝牙/来电切换、双声唤醒的语速/间隔、误唤醒率和插话效果仍必须在目标真机上验收。

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

语音模型与音色由后端的 Nacos 配置统一维护。App 在每次建立语音会话前刷新 `/voice/capabilities`，使用当前 TTS 模型的音色目录；模型升级导致旧音色不可用时，自动改用当前默认音色，中文聊天仅显示支持中文的音色。App 会校验目录所属模型和 PCM 格式，不把供应商特有的模型协议写入录音或播放层。

后端支持的 Realtime / Inference 模型升级仍使用 16 kHz 输入、24 kHz 输出和现有 VCE1 帧。模型或音色配置发布后先重启后端，再重新连接 App；离线模型、8 kHz 专用模型或全新事件协议需要先在后端增加适配。详见后端仓库的 `docs/Voice_API.md`。

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

App 默认使用 USB 真机地址 `http://127.0.0.1:8000`，也可在开发期用 Dart Define 设置初值：

```bash
flutter run \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
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

## 聊天记录

聊天首页使用固定顶栏和底部语音操作区，消息独立滚动。点顶部助手名称或调节图标可随时打开“对话偏好”，切换助手和音色；语音会话进行时不可切换。欢迎卡片仅在空对话时显示，已有消息会直接进入聊天视图。

长对话提供“回到顶部”和“最新消息”快捷入口。停留在底部时自动跟随新回复；向上翻阅时保留阅读位置，并显示新消息数量或“有新内容”。点击提示即可回到最新回复。消息文字支持选择复制；页面兼容深色模式、放大字体和键盘避让，宽屏消息区域限制在 760 像素以内。

登录后点击首页右上角的“记忆与对话”入口，进入个人内容收藏页。“历史对话”查看当前助手最近 30 天有聊天活动的日期；“长期记忆”管理 Mem0 · 小美记住的偏好与习惯。聊天记录列表支持切换助手和下拉刷新；点击日期进入详情，按会话展示当天新增的消息，工具结果可以展开查看。点击“继续这段对话”会返回首页并恢复对应会话的完整历史，随后可继续语音聊天。

列表接入 `GET /{agent_id}/chat-records?user_id=...`，详情接入 `GET /{agent_id}/chat-records/{YYYY-MM-DD}?user_id=...`。两个接口都携带当前登录用户的 Bearer Token 和 user ID，保留后端的账号隔离。日期和显示时间统一遵循后端 UTC 归档口径，详情不包含其他日期的旧消息。服务器返回登录过期、权限不足、日期超期或网络错误时，页面提供对应提示和重试入口。

页面适配系统深色模式、底部安全区域及放大字体，宽屏内容限制在 760 像素以内。读取聊天记录时暂停离线唤醒，退出记录页面后恢复，避免浏览记录时触发语音会话。

## Mem0 后端兼容

### 长期记忆管理

首页“记忆与对话”、个人主页“长期记忆”和聊天记录页的记忆图标均可进入记忆列表。页面沿用奶油白、浅粉和淡紫的卡片设计，适配深色模式、安全区域、小屏、大字体和键盘避让。

记忆列表每页加载 20 条，使用后端 UUID 游标分页，显示“已加载”数量，不冒充总量。详情从服务器读取最新内容；编辑只发送 `text`，按 Unicode 字符校验 1–6000 字符。编辑后或删除后返回列表会刷新。单条删除和清空全部均需确认，清空范围是当前账号在 Mem0 · 小美中的全部记忆，包括尚未加载的页面。删除记忆不会删除聊天记录；删除后仍可在详情中查看变更历史。变更历史使用数字游标，展示新增、更新、删除及前后内容，时间显示为手机本地时间。

| 功能 | 接口 |
| --- | --- |
| 分页列表 | `GET /memories?user_id=...&limit=20&cursor=...` |
| 详情 | `GET /memories/{id}?user_id=...` |
| 编辑 | `PUT /memories/{id}?user_id=...`，正文 `{"text":"..."}` |
| 删除单条 | `DELETE /memories/{id}?user_id=...` |
| 按用户清空 | `DELETE /memories?user_id=...` |
| 分页变更历史 | `GET /memories/{id}/history?user_id=...&limit=20&cursor=...` |

所有请求使用当前登录用户的 Bearer Token 与 user ID，无其他用户切换入口。页面分别处理登录过期、权限不足、记忆不存在、参数错误、服务未启用/忙碌和超时。写操作结果不确定时不自动重试，必须刷新核对后才能再次操作；分页失败保留已有内容。浏览“记忆与对话”时暂停离线唤醒，返回首页后恢复。

首页根据 `/voice/capabilities.default_agent` 选择默认助手，新后端的 `mem0-chatbot` 显示为“Mem0 · 小美”。助手与音色选择上下排列，手机上也能完整显示 Mem0。会话建立后同步保存后端返回的 agent 和 thread ID；切换助手时清空当前页面的旧消息，历史记录仍可查询。如果旧会话的助手不再可用，不会把该线程自动切换给另一个助手。旧后端未下发默认助手时优先使用仍在列表中的 `chatbot`，否则使用首个可用助手。

Mem0 在服务器运行，App 继续使用现有 Bearer Token、语音 WebSocket、PCM 和聊天记录接口。历史消息保留 `response_metadata.memory_status`；聊天详情与恢复的历史分别提示长期记忆未启用、记忆处理完成、检索暂不可用或本轮记忆未保存。`saved` 表示后端已完成记忆处理，不表示一定新增了事实。未知或缺失状态仍可正常展示消息。当前语音事件不下发这个字段，实时回答不额外宣称记忆已保存，状态可在记录详情中查看。

长期记忆是否启用由后端 `MEM0_ENABLED`、pgvector 和模型配置决定。客户端不会自动开启记忆、修改数据库或保存模型密钥；完整会话历史和跨会话长期记忆是不同的能力。联调工具 `tool/check_mem0.dart` 从标准输入读取测试凭据，在内存中验证默认助手、文字调用、语音/PCM、历史记录及跨助手隔离，输出中不包含令牌或消息正文。

## 工程结构

```text
lib/
├── core/api/                  HTTP、WebSocket、DTO、二进制协议
├── core/auth/                 登录态安全存储
├── core/audio/                Flutter 原生音频桥与 sherpa-onnx 唤醒引擎
├── core/config/               运行配置
├── features/auth/             登录、注册与邮箱验证码页面
├── features/voice_session/    会话状态、打断、播放确认、主界面
├── features/conversations/    个人内容收藏页与历史会话
├── features/memories/         长期记忆、编辑与分页变更历史
└── features/settings/         后端与身份设置
android/                       AudioRecord / AudioTrack / Android AEC
ios/                           AVAudioEngine / Voice Processing
test/                          协议契约与 Widget 测试
```

麦克风只有一条采集链路。Android 每 40 ms 发送一块 PCM；iOS 在原生音频线程完成硬件采样率到 16 kHz 的转换。待机音频送入独立 isolate 中的 sherpa-onnx，不上传；进入会话后才发送给后端。模型来源、许可和校验值见 `assets/models/sherpa_kws/MODEL_SOURCE.md`。

文字增量实时显示，收到并交给原生播放器首包 PCM 后才切换到播报状态。Android 12 及以上请求 40 ms 的 AudioTrack 启动阈值，保留原有播放缓冲容量；旧版 Android 和 iOS 沿用各自系统播放器行为。调试版输出每轮首字到首包接收、原生入队的毫秒耗时，控制器的 `responseLatencyMs` 同时保留后端可选 `latency_ms`（使用 `server_` 前缀）。客户端与服务端时钟分别统计，入队、WebSocket 发送和实际声学出声是不同阶段。

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
