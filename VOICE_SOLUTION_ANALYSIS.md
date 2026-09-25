# 语音方案现状、阿里云百炼能力与实施记录

> 调研日期：2026-09-24
> 调研范围：`agent-voice-app` Flutter 客户端与相邻的 `agent-service-toolkit` 后端
> 调研方式：静态阅读源码、测试和项目文档，并对照阿里云及主流语音助手公开资料
> 更新：已按本文推荐方案完成前台离线唤醒、系统降噪/AEC 状态化、本地 VAD 插话、云端二次确认和质量指标；尚未进行真实百炼账号、弱网或手机真机声学验收。

## 1. 结论摘要

当前项目已经不是“录一段音频再转文字”的简单语音功能，而是一套可工作的前台实时语音 Agent 架构：

- App 原生采集 16 kHz PCM、播放 24 kHz PCM，通过自定义 WebSocket 二进制协议与后端通信。
- 后端使用百炼 `qwen3-asr-flash-realtime` 做实时 ASR 和服务端 VAD，使用 `qwen3-tts-flash-realtime` 做流式 TTS。
- 支持实时字幕、Agent 流式文字、分段语音合成、播放进度确认、用户插话、回答取消、旧音频隔离、业务审批、线程历史和 PostgreSQL 持久化。
- Android 已接系统 `VOICE_COMMUNICATION`、AEC 和 NoiseSuppressor；iOS 已接 `voiceChat` 与 Voice Processing。
- 本地唤醒词、自动本地 VAD 插话提示和音频质量指标已实现；后台常驻唤醒、热词/上下文增强、弱网音频协议仍未实现。

因此，当前产品已具备 App 前台环境式唤醒和连续对话，但还不是 Siri、小爱同学、Alexa 那类在锁屏、后台或进程终止后仍可工作的系统级助手。

建议优先级是：

1. 先完成 Android/iOS 真机 AEC、插话、蓝牙、来电和长会话验收，并补齐音频指标。
2. 再增加端侧轻量 VAD，实现“检测疑似插话后立即暂停，云端确认后取消”的自动双阶段插话。
3. 将唤醒作为独立端侧子系统建设，不要把百炼云端 VAD 当作唤醒词。
4. 如果目标是弱网和更成熟的移动端音频前端，再验证迁移到百炼 AOQ 支持的模型/协议；当前 Qwen3 ASR/TTS WebSocket 适配不能直接无缝切换。

## 2. 当前端到端架构

```text
Android/iOS 麦克风
  │  Android VOICE_COMMUNICATION + AEC + NS
  │  iOS voiceChat + Voice Processing + 重采样
  ▼
Flutter：PCM16 / 16 kHz / mono / 40 ms 左右分块
  │  VCE1 二进制帧 + Bearer Token + WebSocket
  ▼
FastAPI VoiceConnection
  ├─ 有界输入/输出队列、顺序号、幂等 event_id
  ├─ 百炼 Qwen3 ASR Realtime + server VAD
  ├─ 最终转写 → LangGraph Agent / 工具 / 审批
  ├─ 回答文字按可朗读短句切分
  └─ 百炼 Qwen3 TTS Realtime → PCM16 / 24 kHz
  │
  ▼
App 原生流式播放器
  ├─ response_id 隔离旧回答
  ├─ 立即暂停/取消/清空
  └─ 实际播完后回报 playback.progress / playback.finished
  │
  ▼
PostgreSQL：session、turn、生成状态、音频状态、已播段
```

这里最有价值的设计不是某一个模型，而是项目把四种不同事实分开了：

- Agent 是否执行完成；
- TTS 是否合成完成；
- 音频是否已经发到 App；
- 用户设备是否真的播放完成。

这能避免“服务端已经生成完，所以用户一定听完了”的错误假设，也让插话后的对话上下文更可靠。

## 3. 当前已经实现的语音技术

### 3.1 Flutter 与原生端

| 能力 | 状态 | 代码事实与说明 |
| --- | --- | --- |
| 原生麦克风采集 | 已实现 | Android 使用 `AudioRecord`，iOS 使用 `AVAudioEngine`；不是 Flutter UI isolate 内做 DSP。 |
| 固定网络音频格式 | 已实现 | 上行 PCM16 16 kHz 单声道，下行 PCM16 24 kHz 单声道；握手时明确声明。见 `voice_session_controller.dart:174`。 |
| 自定义二进制帧 | 已实现 | 45 字节 `VCE1` 帧头，含连接、回答、段和序号；前后端都有大小、UUID、类型和偶数字节校验。见 `voice_protocol.dart:45`、后端 `schema/voice.py`。 |
| WebSocket 双向流 | 已实现 | JSON 传控制事件，二进制帧传 PCM，并关闭 WebSocket 压缩。 |
| 实时字幕 | 已实现 | 支持 partial 与 final；final 才进入 Agent。 |
| 原生流式播放 | 已实现 | Android `AudioTrack`，iOS `AVAudioPlayerNode`；按 segment/response 标记实际播放完成。 |
| 本地立即停播 | 已实现 | 用户点击停止会先清空本地播放，再发 `response.cancel`。见 `voice_session_controller.dart:218`。 |
| 手动插话提示 | 已实现 | UI 的“我要插话”按钮先暂停播放并发 `input.speech_hint`；若云端未确认用户说话，后端 0.8 秒后发 `playback.resume`。 |
| 语音自然插话 | 已实现基础链路 | 播放期间麦克风持续上传；百炼 ASR 发出 `speech_started` 后，后端使当前回答失效并通知 App 清空旧音频。 |
| 旧回答隔离 | 已实现 | App 和后端都按 `response_id` 拒收取消后的晚到文字与音频，不依赖单一“当前回答”变量。 |
| Android AEC | 已接入 | `VOICE_COMMUNICATION` 音源，并在设备支持时启用 `AcousticEchoCanceler`。见 `MainActivity.kt:397-409`。 |
| Android 降噪 | 已接入 | 在设备支持时启用系统 `NoiseSuppressor`。见 `MainActivity.kt:411-414`。 |
| iOS 语音处理 | 已接入 | `AVAudioSession.voiceChat`、`setVoiceProcessingEnabled(true)`、默认扬声器和 Bluetooth HFP。见 `VoiceAudioEngine.swift:109-120`。 |
| 硬件采样率转换 | 已实现 | iOS 使用 `AVAudioConverter` 转成 16 kHz；Android 直接请求 16 kHz。 |
| 音频路由基础处理 | 部分实现 | Android 主动切到通信/扬声器，iOS 允许 Bluetooth HFP；尚未看到完整的设备切换、Audio Focus、来电/系统中断恢复。 |
| 登录与凭据保护 | 已实现 | 百炼 Key 只在后端；App 使用短期 Token。iOS Keychain、Android Keystore AES-GCM 保存登录态。 |
| 本地唤醒词 | 已实现（前台） | sherpa-onnx 1.13.8 + WenetSpeech 3.3M INT8 模型在独立 isolate 中检测“小美”，并保留 1.2 秒环形预录。进入主页后默认启用，无需页面开关。 |
| 后台/锁屏唤醒 | 未实现 | 没有 Android 前台麦克风服务或 iOS 后台语音产品化处理。 |

### 3.2 后端实时语音编排

| 能力 | 状态 | 代码事实与说明 |
| --- | --- | --- |
| 百炼实时 ASR | 已实现 | `qwen3-asr-flash-realtime`，WebSocket 发送 Base64 PCM，接收 partial/final。 |
| 百炼服务端 VAD | 已实现 | `server_vad`，阈值和静音时长可配置；默认代码为 threshold `0.2`、silence `500 ms`。 |
| Manual 断句 | 后端支持、App 未开放 | Schema 和 Provider 支持 `turn_detection=manual` 与 `input.commit`，但 Flutter 创建会话时固定为 `server_vad`。 |
| 百炼实时 TTS | 已实现 | `qwen3-tts-flash-realtime`、commit 模式、PCM 24 kHz，按可朗读短句连续提交。 |
| 可朗读文本清理 | 已实现 | 去除 Markdown 标记、代码块和 URL，再按标点或最大长度切段。 |
| Agent 流式播报 | 已实现 | 普通 chatbot 可以边生成边播；复杂 Agent 默认等待最终消息，减少内部节点和工具内容误播。 |
| 工具/业务审批协议 | 已实现 | 后端发送 tool 与 approval 事件；App 已实现同意/拒绝卡片。工具开始/完成事件目前未看到可视化消费。 |
| 取消语义 | 已实现 | 区分 `execution_status` 和 `audio_status`；chatbot 可取消执行，复杂工具 Agent 不虚构事务回滚。 |
| 有界队列与背压 | 已实现 | 输出、上行音频、输入和 TTS 文本队列均有限长；控制事件具有较高发送优先级。见 `voice/session.py:69-71`。 |
| 音频节奏与协议校验 | 已实现 | 校验序号、connection ID、帧方向、大小，并限制不能明显快于实时速度上传。 |
| 鉴权与用户隔离 | 已实现 | HTTP 与 WebSocket 都校验 Bearer Token、session 所有者、thread 所有者。 |
| 会话容量与生命周期 | 已实现 | 单用户最多两个未过期会话，进程总连接数、会话时长、空闲超时均可配置。 |
| PostgreSQL 持久化 | 已实现 | 保存 session、turn、input 幂等键、生成文字、分段和已播放采样数；默认不保存原始音频。 |
| 重连基础语义 | 部分实现 | 可复用 thread 新建传输连接，并能防第二连接；App 有 `reconnect()` 方法，但未看到自动重试、退避和 UI 入口。 |
| 生产音频可观测性 | 部分实现 | 已上报 AEC/NS 实际状态、RMS、峰值与削波；首字/首包/首音、丢帧、网络抖动和每轮成本仍待补齐。 |

### 3.3 另一条非实时 Streamlit 语音链路

后端还保留一套与 Flutter 实时链路不同的 Streamlit 方案：

- `qwen3-asr-flash`：把完整录音 Base64 后调用 OpenAI 兼容 Chat Completions；
- `qwen3-tts-flash`：完整文本通过百炼 HTTP 原生接口生成 WAV，再由 Streamlit 播放器播放；
- 适合网页录音、一次性转写和非实时播报，不具备移动端实时双工、插话和播放确认语义。

分析和维护时应明确这两条链路，不能把 Streamlit HTTP STT/TTS 的测试通过等同于 Flutter Realtime 已完成真机验证。

## 4. 当前使用了百炼的哪些部分

### 4.1 已使用

1. **Qwen3 实时语音识别**
   - 模型：`qwen3-asr-flash-realtime`；
   - 16 kHz PCM 实时流；
   - 中间转写、最终转写；
   - 服务端 VAD 起止点检测；
   - 中文语言提示。

2. **Qwen3 实时语音合成**
   - 模型：`qwen3-tts-flash-realtime`；
   - WebSocket commit 模式；
   - 系统音色选择；
   - 24 kHz PCM 流式输出。

3. **非实时 ASR/TTS**
   - Streamlit 使用 `qwen3-asr-flash` 和 `qwen3-tts-flash`；
   - 与实时移动端链路相互独立。

4. **同一 DashScope 账号体系**
   - ASR、TTS、千问 LLM 和 Embedding 复用后端 `DASHSCOPE_API_KEY`；
   - Key 没有下发到 App，这个安全边界是正确的。

### 4.2 百炼已有但项目尚未使用

| 百炼或阿里云相关能力 | 当前状态 | 可能价值 |
| --- | --- | --- |
| ASR 热词 | 未使用 | 改善产品名、人名、业务术语识别。 |
| ASR 上下文增强 | 未使用 | 按当前会话、联系人、设备或业务词表动态提升识别。 |
| ASR 情感字段 | 模型可返回、适配器未消费 | 可用于客服情绪提示，但不应直接决定高风险业务操作。 |
| 字/句时间戳 | 当前 Qwen3 Realtime 不返回 | 若要逐字高亮或精确口型/字幕，需改用支持时间戳的 ASR 模型。 |
| 说话人分离 | 未使用 | 会议或多人场景需要，但当前手机个人助手场景优先级较低。 |
| Qwen3 TTS 指令控制 | 未使用 | 可控制语气、情绪或表达风格；需要切换到对应 Instruct 模型并重做验收。 |
| 声音复刻/声音设计 | 未使用 | 个性化音色；同时带来授权、审核和滥用风险。 |
| Omni 原生实时语音对话 | 未使用 | 可降低传统 ASR→LLM→TTS 的拼接感，但会改变现有 LangGraph 工具、文本审计和可控播报架构。 |
| AOQ / WebRTC | 未使用 | 百炼公开资料称 AOQ/WebRTC 内置回声消除与降噪、弱网优于 WebSocket；需要核对目标模型支持和移动 SDK。 |
| 阿里云设备端离线唤醒 SDK | 未使用 | 可做本地唤醒，但属于智能语音交互设备端方案，不是当前百炼 Realtime WebSocket 自带功能。 |
| 阿里云 RTC 智能降噪 | 未使用 | 可作为更强降噪选项，但会引入 RTC/插件、包体、授权和新音频链路。 |

百炼官方说明中，Qwen3-ASR-Realtime 支持 VAD 和 Manual 两种断句方式，并可配置 `threshold`、`silence_duration_ms`；对话场景官方建议更短的静音阈值。项目当前的 `500 ms` 是合理起点，但必须以真机 P50/P95 断句延迟和误截断率调参，而不是只看主观体验。[百炼实时语音识别文档](https://help.aliyun.com/zh/model-studio/real-time-speech-recognition-user-guide)

## 5. 唤醒词应该如何实现

### 5.1 先区分三个概念

- **唤醒词/KWS**：待机状态持续低功耗检测“你好，小助手”等关键词，决定是否进入交互。
- **VAD**：判断有没有人在说话、何时说完，不理解具体说了哪个词。
- **插话/barge-in**：助手播放期间检测用户重新开口，暂停或取消当前回答。

当前项目已有云端 VAD、端侧离线唤醒和自动本地能量 VAD。播放期连续超过下发阈值时，App 会自动发送 `input.speech_hint`；手动按钮仍作为显式兜底入口。

### 5.2 推荐的端云两级唤醒结构

```text
低功耗待机
  └─ 本地 KWS 高召回检测
       ├─ 保存 0.5～1.0 秒环形预录音
       ├─ 播放唤醒反馈音 / 更新显式麦克风状态
       ├─ 建立或恢复后端语音会话
       └─ 上传预录音 + 后续语音
             └─ 云端 ASR/规则做二次确认，过滤误唤醒
```

成熟方案通常不是“一个模型一次判断”。Apple 公布的 Siri 方案是端侧流式高召回 detector、再由高精度 checker、speaker ID 和整句 directed-speech detection 逐级过滤，并使用端侧 ring buffer 保存唤醒前音频。[Apple Voice Trigger System](https://machinelearning.apple.com/research/voice-trigger)

建议为本项目设计这些状态：

```text
dormant → wake_candidate → connecting → listening → thinking/speaking
   ▲            │               │             │
   └─ timeout / false wake ─────┴─────────────┘
```

关键规则：

- `dormant` 时音频只在设备内进入 KWS，不上传云端；
- 唤醒后才开启百炼实时 ASR，降低隐私、流量和费用风险；
- 唤醒前保留短环形缓冲，避免连接期间丢掉用户命令开头；
- 当前后端允许约 3 秒实时节奏裕量，但预录音上传行为仍应做专门协议和测试，不能依赖隐含容差；
- 活跃会话内不必每一轮重复说唤醒词，继续使用 server VAD；
- 播放期间 KWS/VAD 必须消费经过 AEC 的采集流，否则 TTS 很容易把自己唤醒；
- 云端二次确认失败时回到待机，不创建 Agent 轮次；
- 首页默认开启前台离线唤醒，并明确展示隐私说明、麦克风状态和离开主页时的暂停行为；不再提供容易造成状态歧义的首页开关。

### 5.3 引擎选择

#### 方案 A：阿里云设备端离线唤醒 SDK

阿里云官方把语音唤醒描述为离线端设备能力，需要单独的商业 SDK 授权、Appkey、设备标识等，并不包含在当前百炼 ASR/TTS 调用里。[阿里云设备端语音唤醒授权](https://help.aliyun.com/zh/isi/enable-authorization-1)

优点：

- 商业支持和设备端方案完整度可能更高；
- 与阿里云语音产品体系一致；
- 适合明确要做量产设备或长期后台唤醒的项目。

注意点：

- 需要确认 Android/iOS 当前版本、定制唤醒词、授权价格、包体、耗电和隐私合规；
- 官方接入资料涉及 AK、Secret、Appkey 和设备授权，任何长期 Secret 都不能硬编码进 App；应与阿里云确认正式移动端授权流程，并由后端承担可轮换凭据或授权服务；
- 仍需自己处理 Flutter 原生桥、后台限制、环形缓冲、状态机和与当前 AudioRecord/AVAudioEngine 的单麦克风复用。

#### 方案 B：sherpa-onnx 或其他本地 KWS

优点：

- 可完全本地运行，接口和模型更可控；
- 容易与现有原生采集链路复用；
- 无需为每次唤醒调用云端。

代价：

- 自定义中文唤醒词的训练、正负样本、阈值和跨设备泛化由项目负责；
- 需要维护模型包体、CPU/电量、ARM 架构和升级；
- 必须建立误唤醒/漏唤醒的真实测试集。

现阶段建议先用方案 B 做前台或实验性 KWS 验证，待产品确认确实需要后台/量产唤醒后，再比较阿里云商业离线 SDK。不要在尚未完成真机 AEC 验收时先投入大量自定义唤醒训练。

## 6. 降噪、回声消除与自动插话如何实现

### 6.1 当前实现属于“系统音频前端”

目前的处理顺序可以理解为：

```text
扬声器参考信号 ─┐
                 ├─ OS Voice Processing / AEC → NS → 16 kHz PCM → WebSocket
麦克风输入 ──────┘
```

Android 使用系统 AEC/NS，实际效果取决于机型、ROM、扬声器音量和音频路由；iOS 的 `voiceChat` + Voice Processing 通常更一致，但也必须在真机外放、蓝牙、耳机和系统中断场景验证。

当前没有显式接入：

- Android `AutomaticGainControl` 或独立 AGC；
- 独立的 AI 降噪模型；
- 本地 VAD；
- AEC/NS 实际启用状态与效果遥测；
- 音频 RMS、噪声底、削波率、回声残留等质量指标。

不要无条件叠加多套 AEC、NS 和 AGC。系统 Voice Processing、RTC SDK 和第三方 DSP 同时处理，可能造成金属音、吞字和增益泵动。应在固定测试集上一次只替换一个处理层。

### 6.2 建议的自动插话链路

```text
AEC 后音频
  └─ 本地轻量 VAD
       ├─ 疑似人声：立即 pause/duck 本地播放器 + input.speech_hint
       ├─ 云端 ASR speech_started：response.cancel，永久清空旧回答
       └─ 800 ms 内未确认：playback.resume
```

当前后端的“云端确认后取消、未确认则恢复”已经具备，缺的是端侧自动 VAD 触发。这样补齐后，插话首响可以不等待一次网络往返，同时又不会让一次碰撞声永久取消回答。

本地 VAD 阈值应分场景设置：

- 助手未播放：偏高召回，避免漏掉轻声；
- 助手播放中：结合 AEC 残留、连续帧和能量变化，要求更稳定的证据；
- 蓝牙 HFP：单独标定，因为带宽和系统处理链与手机外放不同；
- 远场：不要简单降低阈值，否则电视声和旁人说话会频繁插话。

### 6.3 是否迁移到百炼 AOQ / WebRTC

百炼当前公开对比中，WebSocket 的回声消除/降噪需要客户端自行处理；AOQ 和 WebRTC 内置这些能力，其中 AOQ 更强调移动端与弱网。[百炼 Realtime API 协议对比](https://help.aliyun.com/zh/model-studio/realtime-api-overview)

但该文档列出的 AOQ ASR/TTS 模型主要是 Qwen-Audio/Fun-ASR/CosyVoice 系列，当前项目使用的 `qwen3-asr-flash-realtime` 与 `qwen3-tts-flash-realtime` 不能仅换 URL 就迁移。因此建议：

- 短期继续使用现有 WebSocket + 系统 AEC/NS，先获得真机基线；
- 如果弱网、回声和跨机型一致性成为主要问题，再做 AOQ 技术验证；
- 验证时比较完整链路，而不是只比较 ASR 准确率：建连、首音、丢包恢复、插话、音色、事件兼容、SDK 包体、成本、授权和 LangGraph 接入都要评估；
- 若切到端到端 Omni 语音模型，应保留工具审批、文本审计、执行幂等和播放交付记录，不要为了自然度丢掉现有业务安全边界。

阿里云 RTC 也提供智能降噪组件，但这会引入另一套音频采集/处理体系。[阿里云 RTC Android 智能降噪](https://help.aliyun.com/zh/document_detail/310079.html) 对当前一对一语音 Agent，除非真机数据证明系统 NS 不够，否则不建议只为“看起来更完整”而接入整个 RTC SDK。

## 7. 与主流语音助手的差距

以下比较依据公开可观察能力和厂商资料，不推断其未公开内部实现。

| 维度 | 当前项目 | Siri / Alexa / 小爱等环境式助手 | Gemini Live 类前台助手 |
| --- | --- | --- | --- |
| 启动方式 | 点击“开始语音”或前台本地唤醒 | 本地唤醒词、按键，部分支持声纹 | 通常先进入 Live 会话，也可由系统助手入口启动 |
| 待机隐私 | 前台待机只在本机检测；命中后才上传前滚与实时 PCM | 本地低功耗监听，候选唤醒后才进入云端链路 | 活跃 Live 会话期间持续使用麦克风 |
| 连续多轮 | 已支持 | 成熟 | 成熟 |
| 语音插话 | 已有云端确认、手动 hint、立即停播 | 成熟，通常结合硬件 AFE、AEC 和端云检测 | Gemini Live 公开支持说话打断或点击打断 |
| 远场能力 | 手机单麦克风/系统音频处理 | 智能音箱常用麦克风阵列、波束成形和专用 DSP | 主要依赖手机系统音频前端 |
| 声纹/个人唤醒 | 无 | 部分产品支持 voice match / speaker ID | 依赖账号与设备，不等同于唤醒声纹 |
| 弱网 | 原始 PCM + WebSocket，无重传/抖动缓冲策略 | 产品级私有协议或 RTC/设备协议 | 平台级实时协议 |
| 离线能力 | 唤醒离线；ASR/Agent/TTS 依赖网络 | 部分基础命令、唤醒或 ASR 可端侧完成 | 主要依赖云端 |
| 多模态 | 语音、文字 | 依设备支持屏幕/摄像头/家庭设备 | Gemini Live 支持字幕及部分设备上的相机/屏幕共享 |
| 设备生态动作 | LangGraph 工具可扩展，并有审批机制 | 已有庞大系统/智能家居生态 | 依赖 Google 服务与设备权限 |
| 可审计性 | 很强：文字、工具、状态、播放交付可追踪 | 对第三方开发者通常较封闭 | 产品层可见，对内部执行审计较少开放 |

当前项目并非全面落后：它在“工具执行与音频播放是否完成的区分”“取消不伪造业务回滚”“旧响应隔离”这些 Agent 工程语义上，比很多简单语音 Demo 更严谨。差距主要在环境式唤醒、远场声学、弱网、系统生命周期和大规模真机验证。

公开参考：

- Apple 的唤醒系统采用端侧多阶段检测、ring buffer 和 speaker ID：[Voice Trigger System for Siri](https://machinelearning.apple.com/research/voice-trigger)
- Alexa 公开设计要求支持 wake word、PTT、Speaking/Thinking 状态下 barge-in，并明确可见/可听的 attention state：[Alexa Invoking and Interruption](https://developer.amazon.com/en-US/docs/alexa/alexa-auto/invoking-alexa.html)
- Gemini Live 支持在助手说话时用语音打断，也保留点击打断，并支持字幕和后台/锁屏持续会话条件：[Gemini Live Help](https://support.google.com/gemini/answer/15274899?hl=zh-Hans)
- 小爱公开资料体现唤醒词、声纹和连续对话的产品形态：[小爱开放平台语音隐私说明](https://developers.xiaoai.mi.com/documents/Home?type=%2Fapi%2Fdoc%2Frender_markdown%2Fnew%2FXiaoaiVoicePrivacy)

## 8. 目前最值得关注的缺口与风险

### P0：上线前必须验证

1. **真实百炼联调证据不足**
   - 后端有较完整的 Fake Provider 契约测试，HTTP STT/TTS 也有 mock 测试；
   - 不能由此推导真实 Realtime 事件、配额、超时、区域地址和异常事件全部兼容。

2. **真机声学没有量化验收**
   - AEC/NS API 被调用不等于效果达标；
   - 应覆盖高音量外放、安静/噪声、近讲/远讲、男女性声音、连续插话和不同机型。

3. **音频焦点、路由和系统中断不完整**
   - Android 未看到完整 Audio Focus、设备变化回调；
   - iOS 未看到 interruption/route change notification 的恢复状态机；
   - 来电、闹钟、蓝牙切换和锁屏可能造成录放不同步或资源未释放。

4. **弱网成本较高**
   - 上行 PCM16 16 kHz 约 `32 KB/s`，持续 30 分钟约 `57.6 MB`，还不含协议和后端到百炼 Base64 膨胀；
   - 下行 PCM16 24 kHz 约 `48 KB/s`，按实际播报时长产生；
   - 没有 Opus、抖动缓冲、网络质量自适应或断线自动恢复。

5. **前后端能力展示尚不完全一致**
   - 后端产生 `tool.started`、`tool.finished`、`agent.custom` 等事件，Flutter 当前事件处理没有展示它们；
   - App 有 `reconnect()`，但没有找到自动重连或显式 UI 入口；
   - Manual 断句存在于后端，App 固定使用 server VAD。

### P1：体验与可运营性

- 本地自动 VAD 和自动 `speech_hint`；
- 首字、最终转写、Agent 首 token、TTS 首包、设备首音的分段时延；
- ASR 空结果、误断句、插话误触发、TTS 失败、取消后晚到帧计数；
- AEC/NS 是否可用、音量 RMS、削波、静音比例；
- 每会话 ASR 秒数、LLM token、TTS 字符/秒数和估算成本；
- 真实设备矩阵与版本回归。

### P2：环境式助手能力

- 本地唤醒与环形预录；
- 后台/锁屏策略；
- 唤醒声纹或至少个性化阈值；
- 本地基础命令或断网降级；
- 多设备协同唤醒与隐私设置；
- 远场麦克风阵列只应在硬件产品目标明确后考虑。

## 9. 推荐实施路线

| 阶段 | 建议内容 | 验收标准 |
| --- | --- | --- |
| 1. 建立真机基线 | 保持现有 WebSocket 架构；真实百炼联调；补 Android/iOS 音频中断和路由测试；采集时延与声学指标 | 30 分钟/50 轮；停止到静音 ≤200 ms；高音量外放仍能插话；旧音频不复活 |
| 2. 自动双阶段插话 | 在 AEC 后增加本地轻量 VAD，自动 pause + hint，云端确认后 cancel | 噪声下误暂停可恢复；真实人声插话明显快于单纯等待云端 |
| 3. 识别质量增强 | 接入业务热词/上下文增强；按场景调 VAD；消费或明确忽略 emotion | 业务词集准确率提升，普通词准确率不明显下降 |
| 4. 前台唤醒试验 | 复用唯一麦克风链路，引入本地 KWS 和 0.5～1 秒 ring buffer | 统计漏唤醒率、每小时误唤醒、唤醒到首音、电量和包体 |
| 5. 产品化唤醒 | 决定阿里云商业离线 SDK 或自维护 KWS；处理后台、授权、隐私与声纹 | Android/iOS 目标系统版本和机型矩阵达标 |
| 6. 协议升级评估 | 当弱网成为真实瓶颈时，再对 AOQ/WebRTC/Opus 做 A/B 验证 | 弱网首音、连续性、耗电和成本相对现方案有明确收益 |

## 10. 最终建议

如果产品定位是手机上的前台 Agent 助手，当前“端侧系统 AEC/NS + 百炼实时 ASR/TTS + LangGraph”的技术方向是合适的，不必为了追求概念完整度立即切换到端到端语音模型或整套 RTC。

如果产品定位是类似小爱、Siri 的环境式助手，则唤醒词不是给后端加一个接口就能完成，而是一个独立的端侧音频产品工程，至少包括：低功耗 KWS、环形预录、误唤醒复核、隐私指示、后台生命周期、声纹/个性化、AEC 后检测、真机功耗和大量声学数据验证。

当前最合理的下一步不是先选一个“更高级”的模型，而是把已有链路在真实设备上量化。只有得到回声残留、插话延迟、误断句、弱网和成本数据后，才能判断下一笔工程投入应该落在本地 VAD、唤醒、AOQ，还是更强的 ASR/TTS 模型上。

## 11. 主要代码依据

### 前端

- `lib/core/api/voice_protocol.dart`：VCE1 帧、UUID、序号和 PCM 校验
- `lib/core/api/voice_socket.dart`：WebSocket JSON/二进制消息
- `lib/features/voice_session/voice_session_controller.dart`：会话、字幕、取消、插话、播放确认
- `android/app/src/main/kotlin/com/coderpwh/agent_voice_app/MainActivity.kt`：Android 采集、AEC、NS、路由、播放
- `ios/Runner/VoiceAudioEngine.swift`：iOS Voice Processing、重采样和播放确认
- `README.md`：前台离线唤醒实现、模型来源及真机验收边界

### 后端

- `../agent-service-toolkit/src/service/voice.py`：HTTP/WebSocket 路由、鉴权与容量
- `../agent-service-toolkit/src/schema/voice.py`：协议、事件和持久化模型
- `../agent-service-toolkit/src/voice/session.py`：实时并发、ASR、Agent、TTS、取消和播放状态
- `../agent-service-toolkit/src/voice/providers/alibaba_realtime.py`：百炼 Realtime ASR/TTS 适配
- `../agent-service-toolkit/src/voice/speech_output.py`：可朗读文本切段与清理
- `../agent-service-toolkit/src/voice/persistence.py`：PostgreSQL session/turn/播放进度
- `../agent-service-toolkit/src/voice/providers/alibaba_stt.py`：Streamlit 非实时 ASR
- `../agent-service-toolkit/src/voice/providers/alibaba_tts.py`：Streamlit 非实时 TTS
- `../agent-service-toolkit/tests/voice/test_realtime_service.py`：模拟 Provider 下的流式、取消、背压、重连、审批和持久化测试

## 12. 外部资料

- [百炼实时语音识别](https://help.aliyun.com/zh/model-studio/real-time-speech-recognition-user-guide)
- [百炼语音合成模型与能力](https://help.aliyun.com/zh/model-studio/tts-model)
- [百炼 Realtime API：WebSocket、WebRTC 与 AOQ](https://help.aliyun.com/zh/model-studio/realtime-api-overview)
- [百炼 Qwen TTS Realtime WebSocket](https://help.aliyun.com/zh/model-studio/interactive-process-of-qwen-tts-realtime-synthesis)
- [阿里云设备端语音唤醒授权](https://help.aliyun.com/zh/isi/enable-authorization-1)
- [阿里云 RTC Android 智能降噪](https://help.aliyun.com/zh/document_detail/310079.html)
- [Apple Voice Trigger System for Siri](https://machinelearning.apple.com/research/voice-trigger)
- [Alexa 唤醒、状态与打断设计](https://developer.amazon.com/en-US/docs/alexa/alexa-auto/invoking-alexa.html)
- [Gemini Live 官方帮助](https://support.google.com/gemini/answer/15274899?hl=zh-Hans)
- [小爱开放平台语音隐私说明](https://developers.xiaoai.mi.com/documents/Home?type=%2Fapi%2Fdoc%2Frender_markdown%2Fnew%2FXiaoaiVoicePrivacy)
