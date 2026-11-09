# 对话执行过程

助手消息内显示可折叠的执行过程，沿用 AppPalette 和现有排版。进行中显示当前步骤，
成功后默认折叠，失败、待核实、等待补充信息或确认时默认展开。步骤同时使用文字和图标，
实际耗时来自后端，不展示推算的百分比或模型内部推理。

## 数据与边界

`lib/core/api/execution_models.dart` 解析版本 1 的 `execution.progress` 完整快照。
实时来源为 `agent.custom.data`，历史来源为 `response_metadata.execution`，恢复来源为
`GET /{agent_id}/executions?thread_id=...`。按 run_id 合并，拒绝较低序号；原有不带执行
摘要的消息保持兼容。执行状态与连接/收音/播放状态及视频后台任务状态分别维护。

恢复查询由后端验证线程所有权，前端不从自然语言推断任务或确认。实时快照中的全文不
写入正在接收的文字流，避免与 text.delta 重复；恢复结果仅用于展示，不进入音频队列。
重新连接不会重提已提交的业务操作。运行中快照长时间无更新时由后端标记待核实。

记忆确认按钮显示服务端预览，提交 memory.confirm，包含 confirmation_id 和 approved。
仅当前消息中的有效确认可提交，本地防重复；后端再校验当前待处理操作、有效期和所有权。
旧历史详情只读。LangGraph 原有审批卡片保持独立。结果不明确时先刷新核实，不自动重试。

## 视频与资源释放

VoiceSessionController 按视频记录 ID 去重查询现有 /videos/{id}，同时更新消息和列表中的
相同任务。继续复用 VideoReference 的生成状态、存储状态和播放地址校验。每 10 秒刷新，
每个任务最多 120 次，终态停止；不创建任务，不自动播放。后台暂停刷新，返回前台恢复；
清空聊天、切换账号/服务地址和 dispose 使旧请求失效，迟到结果不能覆盖新会话。

## 验证位置

- test/features/execution_events_test.dart：事件去重、恢复、文字不重复、视频刷新和确认提交。
- test/features/execution_progress_test.dart：协议边界、按钮状态、小屏/200% 字体与深浅色布局。
- 原有 voice_session_controller、voice_video_events、voice_home_page 和聊天历史测试继续回归。

可设置 EXECUTION_SCREENSHOTS=1 运行 execution_progress_test，将视觉核对图片写入
被忽略的 build/execution-preview/；这些图片不代表真实模型、原生播放或真机联调结果。
