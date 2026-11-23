# 图像工作室

从语音首页的相册图标打开「图像工作室」。窄屏或系统大字号下，从「创作工具」菜单进入。图像和视频分别打开各自的工作室，记忆、历史对话和个人主页仍从原有入口访问。有图像任务的语音回复和历史消息会显示可点击的任务卡片。

## 创作流程

1. 在「新建图像」输入画面描述。可以留下标题和画幅，也可以添加最多 3 张参考图。提示词最多 4,000 个 Unicode 字符，标题最多 200 个。
2. 从系统相册选图。客户端验证文件格式和 10 MB 大小上限，调用 `POST /files` 上传。返回的 `url` 用于预览，返回的 `id` 随 `source_file_ids` 提交，后端据此验证素材归属。支持 JPG、PNG、WebP、BMP、TIFF、GIF。部分设备无法预览 TIFF，可以继续提交已上传素材。
3. 提交后立即查看任务。运行、排队和云端保存期间，可以返回列表或关闭 App。重新打开工作室可以继续查看任务。
4. 已完成图像可以放大浏览。选择「继续编辑」，填写修改描述，也可以追加最多 2 张参考图。成功提交后，新的编辑任务和原图分别保留。
5. 图像详情菜单可以修改标题。终态可以删除，需二次确认。删除后该任务从 App 的作品列表移除。

## 接口与状态

| 操作 | 请求 | 说明 |
| --- | --- | --- |
| 素材上传 | `POST /files` | 复用 `FileApi`。multipart 字段为 `file`，使用返回的 ID 和 URL |
| 生成 | `POST /images` | `prompt`、可选 `title`、`source_file_ids`、`size`。HTTP 202 返回任务 |
| 编辑 | `POST /images/{id}/edits` | 使用已有图像作原图，同样返回新任务 |
| 列表 | `GET /images?page=1&page_size=20` | 使用服务端分页，按任务 ID 去重 |
| 详情 | `GET /images/{id}` | 通过本地记录 ID 查询，支持手动刷新 |
| 更新标题 | `PATCH /images/{id}` | 只发送 `title`，使用响应更新任务 |
| 删除 | `DELETE /images/{id}` | 成功响应包含 `deleted=true`，回到列表并刷新 |

生成和编辑携带 `Idempotency-Key`。网络中断、超时或 5xx 时保留本次请求参数和幂等键，用户选择「确认提交」才会重试。上传失败需要单独确认重传或移除参考图，上传期间不能提交。返回同一个工作室内的对应表单时可以继续核实该请求。

列表和详情在前台每 5 秒查询活跃任务。列表按已加载的活跃页轮询，每次只查一个页。回到前台或从详情返回会重新加载。任务进度使用服务端状态，取到 `SUCCEEDED` 与有效 `image_url` 后显示七牛云成图，预览请求无需 App Bearer 令牌。

也可以在语音对话中说「查一下四十二号图片的详情」「帮我找标题叫远山的图片」或「找一下画着蓝色小船的图片」。画面关键词匹配生成描述。语音页面使用 `response_id` 关联 `image.task` 单条结果和 `image.list` 多条结果，历史通过执行进度的 `image` 或 `image_results` 恢复。单图预览完整画面，多图使用带标题和编号的图集，窄屏或大字号使用单列。图片加载失败可重试，点击卡片读取最新详情，打开期间保留语音会话。

按编号、标题或画面关键词未命中时，语音首页展示近 72 小时创建的图片任务，并按时间从新到旧列出最多六张。图片卡片显示编号、创建日期以及任务状态。App 在前台周期刷新生成中的图片卡片，云端保存完成后在原位置显示成图。

## 界面取舍

图集在常规字号和足够宽的内容区使用双列，窄屏或大字号使用单列。详情按成图的实际比例完整展示，并根据屏幕限制竖图高度。点击图片可进入原图查看页缩放。图集、详情、编辑预览和原图查看页复用已解码成图。详情显示加载进度提示，图片请求最多等待 15 秒，失败或超时可重新加载。

暖白、墨黑和低饱和橄榄色沿用 `AppPalette`，图集使用项目的宋体标题与留白。创作入口、进行中的任务和最终成图分别提供明确操作与状态文字。参考 Android 关于导航与主要操作分层的建议，和 Apple 对耗时未知任务使用不定进度提示的建议。[Android 布局与导航](https://developer.android.com/design/ui/mobile/guides/layout-and-content/layout-and-nav-patterns) · [Apple 进度指示](https://developer.apple.com/design/human-interface-guidelines/progress-indicators) · [Design at Meta](https://www.meta.com/design-at-meta/blog/the-new-instagram-brand-identity/)

## 本地与 USB 验证

```sh
flutter analyze
flutter test test/core/image_api_test.dart test/features/image_studio_test.dart test/features/voice_image_events_test.dart
./scripts/install_usb_debug.sh
```

正常 Debug APK 从 `lib/main.dart` 构建。脚本按手机已安装版本递增构建号，覆盖安装并通过 `adb reverse tcp:8000 tcp:8000` 将手机的 `http://127.0.0.1:8000` 映射到电脑本地服务。USB 重连后重新建立映射。

只读真机测试入口为 `integration_test/image_backend_ui_test.dart`，驱动为 `test_driver/image_backend_ui_test.dart`。需在对应账号下准备已转存的测试图，可用 `IMAGE_TEST_ID` 限定记录。测试覆盖登录态访问、真实列表与详情、七牛图片解码、工作室入口、新建和编辑表单。默认使用手机安全登录态，也可用仓库已有的一次性 USB 测试身份桥。以覆盖安装和 `flutter drive --use-existing-app=... --keep-app-running` 运行测试包，避免卸载业务 App。完成测试后执行安装脚本恢复正常入口。截图输出到 `build/image-ui-verification/`。

### 2026-11-22 真机验收

- Dart 分析通过。Flutter 全量测试 226 项通过、1 项跳过，覆盖上传完成后提交、幂等复用、异步刷新、标题修改、删除、历史卡片，以及 320 px 和 200% 字号布局。
- Android 真机 M2011K2C 使用隔离测试身份读取本地后端的列表和详情。图库、详情和编辑页实际绘制七牛图像。验证首页入口、新建和编辑表单，并检查 `build/image-ui-verification/` 内的五张截图。
- 正常入口 Debug APK 构建号 107，已覆盖安装并启动。服务地址 `http://127.0.0.1:8000` 通过 USB 反向映射连接本地后端，已清理测试桥映射。APK 路径为 `build/app/outputs/flutter-apk/app-debug.apk`。
