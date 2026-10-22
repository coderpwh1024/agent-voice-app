# 视频工作室

独立模块位于 `lib/features/videos/`：`data/` 维护请求与契约，`video_studio_page.dart` 维护作品列表，`video_create_page.dart` 维护生成表单，`video_detail_page.dart` 维护查询、轮询和播放器，`video_widgets.dart` 维护视觉组件。复用现有 `AgentApiClient` 的 Bearer 认证和统一响应解析；不持有模型或七牛密钥。

## 入口与设计

首页右上角的影片图标进入视频工作室；“记忆与对话”也提供同一入口。打开工作室时暂停本地唤醒，返回首页后恢复。正在语音通话时禁用入口，避免影片播放与语音采集冲突。

视觉采用奶油白、莓粉、圆角留白、电影画幅与原创日落插画，支持系统深色模式、小屏和大字体。设计参考 [MaMuN AhAmEd 的 AI 视频移动端作品](https://dribbble.com/shots/26936923-AI-Video-Generator-Mobile-App-Design) 对创作入口与工具层级的组织方式，页面插画由 Flutter 绘制，不依赖远程图片。插画标明“非生成效果预览”；作品卡片使用影片图标，不把插画作为实际视频缩略图。

## 接口

已核对相邻后端仓库 `docs/Video_API.md`、视频 schema、路由、服务与运行中的 `/openapi.json`。整体后端还包括邮箱认证、用户资料、语音会话、聊天调用/流式/历史/归档、长期记忆、邮件技能及 AG-UI；新增模块沿用现有认证和服务地址。

| 操作 | 接口与行为 |
| --- | --- |
| 生成 | `POST /videos`，带 `Idempotency-Key`，解析 HTTP 202 中的统一响应 |
| 列表 | `GET /videos?page=1&page_size=20`，按需传 `status`、`storage_status` |
| 详情 | `GET /videos/{record_id}`，可从列表进入或按编号查询 |

身份由当前 Bearer 令牌绑定，不向视频接口发送 `user_id`。列表显示后端真实 `total`，按后端页码加载，去除并发变化可能带来的重复 ID。筛选包括全部、已完成（生成成功且已转存）、生成中、排队中、生成失败；其他状态仍可在“全部”与详情查看。分页失败保留已加载作品，刷新失败可重试原刷新。

表单支持两个 HappyHorse 模型、全部九种比例、480P/720P/1080P、3–15 秒、水印与可选随机种子。1.0 模型不会发送 480P。按 Unicode 码点验证最多 5000 字符及最多 2500 个中日韩统一表意文字，种子范围 0–2147483647。

同一次提交在重试时使用原幂等键和参数；请求中禁用重复点击和返回。返回未知结果时锁定参数，并允许核对原提交。在当前工作室中重新打开表单仍保留该次待确认提交。此状态只保存在内存；退出工作室或重启 App 后，应先在作品列表核实已提交任务，避免主动新建重复需求。后端返回 `SUBMISSION_UNKNOWN` 时详情明确要求核实，不自动重新生成。

详情页仅在前台每 10 秒查询尚未完成的任务，最多连续自动查询 60 次；切后台暂停，回前台重新核对。查询失败停止自动请求并提供手动刷新。已完成、失败、取消、失效、提交待核实分别展示；生成成功但转存失败保留成功事实并提示后台会重试，不展示虚假的进度百分比。

只有 `status=SUCCEEDED`、`storage_status=STORED` 且七牛 URL 为有效 HTTP(S) 链接时才加载播放器与提供复制链接。阿里云临时签名链接不展示、不复制。播放器使用 Flutter 官方 `video_player`，支持播放、暂停、拖动进度、缓冲和失败重试；离开 App 时暂停，页面销毁时释放资源，不自动开始播放。

后端公开任务结构不包含提示词、时长、画幅与模型参数，列表/详情不伪造这些字段。

## 验证与真机安装

```sh
flutter analyze
flutter test
./scripts/install_usb_debug.sh 20b2a515
```

脚本构建正常入口 Debug APK、递增手机已安装的构建号、覆盖安装并启动应用。服务地址为 `http://127.0.0.1:8000`，通过 `adb reverse tcp:8000 tcp:8000` 访问电脑本地后端；不是 Android 模拟器专用的 `10.0.2.2`。USB 重连后应重新执行脚本或建立反向映射。

真机联调使用手机已有安全登录态，不导出令牌。它验证资料、语音能力、聊天记录、长期记忆，以及视频创建、重复幂等提交、列表、查询、实际生成、转存、下载和原生播放，并输出页面截图。会生成一条真实 3 秒 480P 测试影片并消耗服务端额度；同一测试键可重复执行而不新增影片。运行前需要已登录且后端启用视频模块：

```sh
flutter build apk --debug --build-number=<高于手机当前版本> \
  --target=integration_test/video_backend_test.dart \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
# 将生成的测试 APK 复制到单独路径后运行；避免与最终正常入口 APK 混淆。
flutter drive -d 20b2a515 --keep-app-running \
  --driver=test_driver/video_backend_test.dart \
  --target=integration_test/video_backend_test.dart \
  --use-application-binary=<测试APK路径>
./scripts/install_usb_debug.sh 20b2a515
```

结果与截图位于 `build/video-verification/`，不会提交登录凭据。联调测试明确断言生成与保存成功，服务未启用或上游失败时不会误报通过。若返回 `503 视频生成功能未启用`，需要在本地 Nacos 的应用 YAML 中设置 `video.enabled: true` 后重启；开关在启动时读取。

注意：Flutter 3.47 的 `flutter drive` 默认会在结束时卸载测试应用。复用正常应用包名和已有登录态时必须传 `--keep-app-running`；测试完成后用安装脚本覆盖恢复正常入口，避免卸载导致本地登录态丢失。

## 本次验收记录（2026-10-22）

- `flutter analyze` 无问题；`flutter test` 全部 86 项通过，包含原有语音、唤醒、记忆、历史对话回归和新增视频契约/页面测试。
- USB 真机：小米 M2011K2C，序列号 `20b2a515`，实际 Android 设备。
- 本地 Nacos 缺少视频节点，已按 CAS 校验追加 `video.enabled: true` 并重启本地服务；未变更后端源码或已有业务配置。
- 第一次带原登录态的真机检查已通过用户资料、语音能力、聊天归档和长期记忆，随后视频接口因未启用返回 503。
- 初次使用 Flutter drive 的默认清理行为导致本地登录态丢失，已恢复安装正常版本并明确要求后续保留应用；云端用户资料与内容未删除。
- 后续采用独立测试身份，确认其不是现有注册账号；短期应用令牌通过一次性本机 USB 桥传入测试进程，不持久化到手机登录态，也不写入最终正常 APK。测试支持可选 `VIDEO_TEST_AUTH_BRIDGE`，默认仍从手机安全存储读取登录态。桥接方式必须仅绑定本机回环地址，使用短期独立测试令牌，消费一次即关闭。
- 创建 3 秒 480P 海边日落影片，任务 #1 最终为 `SUCCEEDED / STORED`；重复幂等提交、列表、详情、真实模型生成、七牛持久转存、HTTP 下载和手机原生播放均通过。该测试影片归属独立测试身份，不写入真实用户作品集。
- 真机截图：`build/video-verification/video-studio.png`、`video-create.png`、`video-detail.png`。结果在 `backend-result.json`。
- 最终正常入口包为 `lib/main.dart`，构建号 27，覆盖安装到上述真机；API 地址 `http://127.0.0.1:8000` 通过 USB reverse 映射到电脑本地服务。

为避免驱动安装失败时触发 Flutter 的自动卸载重装，已有数据的设备建议先通过 `adb install -r` 覆盖安装测试包，再使用 `flutter drive --use-existing-app=<已运行测试应用的本机VM地址> --keep-app-running` 附加验证。测试结束使用安装脚本覆盖恢复正常入口。不要卸载应用来排查 MIUI 的安装拦截。
