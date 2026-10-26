# 语音消息中的链接与图片

实时语音页与聊天历史详情复用 `lib/core/content/` 的消息组件。沿用暖白、墨黑、橄榄色和现有消息气泡，保持正文可选择复制；链接以下划线区分，图片与动图作为紧凑附件展示，不为每个网址增加网页大卡片。

## 后端契约核对

已阅读相邻后端 `docs/Voice_API.md`、`src/schema/schema.py` 的 `ChatMessage`、`src/voice/session.py` 的流式输出，以及 `src/service/utils.py` 的历史消息转换；同时读取当前服务 `/openapi.json`。后端 `text.delta.text` 是字符串增量，历史 `ChatMessage.content` 是字符串，前端保留原文，只改变展示。后端转换多模态列表时当前仅提取文本块，因此本次不声称支持后端尚未交付的独立图片块。

无需新增接口，也不修改 PCM、VCE1、认证、语音取消或播放确认协议。`ConversationEntry.isStreaming` 只用于展示：文字生成期间不请求图片，收到 `response.done` 后显示预览；取消及断线结束展示中的流式状态。继续沿用已取消回答的迟到事件过滤。原有 `agent.custom` 视频卡片保持结构化契约，不从普通 MP4 URL 推断视频任务或创建生成请求。

## 支持范围

| 内容 | 展示与操作 |
| --- | --- |
| HTTP／HTTPS 裸链接、www 地址 | 正文显示可点击链接，兼容中文标点、查询参数及长地址换行；www 使用 HTTPS |
| Markdown 链接 | 显示链接文案，点击交给外部应用打开；打开失败可复制地址 |
| Markdown 图片、常见图片 URL | 识别 JPEG、PNG、GIF、WebP、BMP 等图片地址，下载后校验实际格式，保持原比例预览；点击放大，可复制或打开原图 |
| 无扩展名图片 | Markdown 图片可显式声明；裸地址对 `/static/`、`/assets/`、`/media/` 和已有上传 `/users/.../files/...` 形态尝试图片预览；实际图片以内容校验为准 |
| 根路径静态资源 | 相对地址按当前服务地址解析；正文自动识别 `/static/`、`/assets/`、`/media/`、`/files/`，Markdown 可声明其他有效根路径 |
| Unicode 表情、Markdown 表情短码 | 使用系统字体显示；例如 `:smile:` 可显示为表情，不新增运行时下载字体 |
| GIF 表情包 | 原生动画预览，使用更紧凑的高度；尊重系统减少动画设置 |
| PDF、音视频、压缩包或其他资源 | 保留超链接，由系统外部应用／浏览器处理，不在文字消息中自动播放、下载保存或创建视频任务 |
| 不支持内嵌解码的图片（例如 SVG）或加载失败 | 正文与地址保留，提供重新加载、打开链接和复制入口，不把整个回答标记为失败 |

共用 Markdown 渲染兼容段落、列表、引用及代码等基本格式；不执行返回的 HTML 或脚本，代码中的地址不自动当成图片。资源去重后默认显示前三张，其余可主动展开。图片放大页使用缩放查看器，长地址可滚动阅读和复制。

## 资源与交互规则

- 只打开有效且无内嵌凭据的 HTTP(S) 地址；不执行 `javascript:`、`data:`、`file:` 或 Intent 地址。不将未知文本当作控制指令。
- 图片请求使用独立 HTTP 客户端，不携带应用 Bearer 令牌。限制单图 8 MiB、总请求 15 秒、最多跟随三次跳转；逐跳验证目标地址，退出后释放客户端。
- 预览解码限制宽度，减少大图内存占用；加载失败不丢弃正文和原链接，不自动无限重试。
- 单次视频和网页资源打开保持不同语义；网页链接使用 `url_launcher` 的外部应用模式，失败提供复制。系统应用锁等认证界面由用户自行完成。

## 联网参考与实现取舍

- [Slack：Formatting message text](https://docs.slack.dev/messaging/formatting-message-text/) 说明直接 URL 和带文案链接的消息表达方式；本项目采用正文链接加独立图片附件的层次，不复制 Slack 品牌界面。
- [Flutter：Image](https://api.flutter.dev/flutter/widgets/Image-class.html) 说明原生支持 JPEG、PNG、GIF／Animated GIF、WebP／Animated WebP、BMP 等格式，支持限制解码尺寸，以及减少动画下的多帧图片行为。
- [Flutter 官方插件：url_launcher](https://pub.dev/packages/url_launcher) 提供系统浏览器／外部应用打开 URL 的能力；按照其建议直接尝试打开并处理失败，不使用可用性预判误禁用可打开的链接。
- [Flutter Markdown Plus](https://pub.dev/packages/flutter_markdown_plus) 是原 Flutter Markdown 的延续，支持可选择正文、链接回调和自定义图片组件。本项目使用统一样式和图片组件，而不加载返回的 HTML 页面。

## 本轮验证（2026-10-25）

- `flutter analyze` 无问题；全套 161 项测试通过，1 项与本次无关的可选视频截图审计跳过。新增测试覆盖 URL 校验、Markdown、去重、代码块、资源请求与跳转、8 MiB 限制、失败重试、复制、320px／200% 文字和深浅色；原有语音、视频交接、历史与其他模块回归通过。
- 小米 M2011K2C（`20b2a515`）以受控消息进行 UI 验证，真实 HTTP 读取电脑端程序绘制的 PNG／GIF，确认图片放大与复制、无扩展名／根路径静态图片、历史兼容、流式期间不请求图片、失败重试和 200% 字体深浅色。GIF 原生解码观察到 3 帧事件；资源请求没有应用认证头。8 张截图与结果位于 `build/message-ui-verification/`。
- 浏览器跳转已触发系统应用锁。未读取或绕过密码，取消该次打开后返回本应用完成其他检查；网页最终加载未验收，结果明确保留 `external_browser_loaded_link=false`。待用户自行解锁浏览器后可补验。受控 UI 验证不等同于真实 STT／TTS 语音通话验收，本轮没有创建实际语音网络会话或付费视频任务。
- 最终包为正常 `lib/main.dart` 入口 `1.0.0+69`，USB 覆盖安装保留用户数据。编译地址为 `http://127.0.0.1:8000`，通过 reverse 8000 访问电脑后端；8766 仅供本轮测试资源，不进入最终包配置。安装包、截图和报告均在忽略的 `build/` 下。
