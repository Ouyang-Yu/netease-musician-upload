---
name: netease-musician-upload
description: >-
  End-to-end zero-focus, zero-popup workflow for preparing audio/cover assets
  and uploading or publishing songs to NetEase Cloud Music Musician
  (网易音乐人 / 网易云音乐人, music.163.com/musician) using a dedicated persistent
  Chrome CDP instance (~/.chrome-agent-profile on port 9223). Use when the user
  asks to upload tracks, create albums, fill remix/AI metadata, or publish music
  on NetEase Musician.
---

# 网易音乐人（NetEase Musician）零焦点、零弹窗自动上传指南

使用独立持久化专用 Chrome 实例（`~/.chrome-agent-profile` + CDP 端口 `9223`）完成网易音乐人作品预处理、后台上传、新建专辑、填报元数据并推进至最终「签约授权」页。

- **最多登录一次，永久复用**：独立 `--user-data-dir` 持久保留网易音乐人登录 Cookie 与会话，重启后仍免登录。
- **0 弹窗、0 焦点**：独立实例开放标准 `/json/version` 与 CDP WebSocket，不触发 Chrome 144+ 主力浏览器的按连接「允许远程调试」授权框，也不碰用户日常主 Chrome 或抢占窗口焦点。

---

## 1. 通道选型与工具边界（防踩坑护栏）

1. **首选专用持久化 Chrome 实例（0 弹窗）**
   - 执行 [ensure_chrome.sh](./scripts/ensure_chrome.sh) 检查或自动后台拉起专用 Chrome（监听 `http://127.0.0.1:9223`），从输出 JSON 的 `webSocketDebuggerUrl` 建立连接。
   - **禁止使用内置 `/browser` 子代理**：内置受限沙盒访问 `musician.163.com` 会报连接关闭或超时，且无法持久保存桌面代理与创作者登录态。
   - **禁止使用 `agent-desktop` 点击网页上传框**：Chromium 安全机制会拦截后台 AX 点击触发的隐藏 `<input type="file">`，必须用 CDP `DOM.setFileInputFiles` 直接注入文件。
2. **如临时回退连接用户主力 Chrome（Chrome 144+ `DevToolsActivePort`）**
   - **严禁每步起短生命周期脚本反复断连重连**：每新建一条 WebSocket 都会触发主力 Chrome 弹一次「允许远程调试」确认框。
   - 必须将同阶段的页面建 tab、上传、填表、推进与截图全部合并在**单条持久 WebSocket 连接**内完成。
3. **零焦点与直达上传页**
   - 严禁调用 `Target.activateTarget`、`Page.bringToFront`、`agent-desktop --headed` 或 `focus-window`。
   - 无需从首页多层点击导航，直接后台创建上传页标签：
     ```js
     await cdp.send("Target.createTarget", {
       url: "https://music.163.com/musician/artist/manage/album/nalbum/songupload",
       background: true
     });
     ```
   - 等待 `document.readyState === "complete"` 且出现上传提示或 `input[type="file"]`；若跳转至登录页，仅在首次未登录时提示用户在专用 Chrome 窗口手动登录一次，后续永久复用。

---

## 2. 前置本地校验与素材准备（先于网页操作）

1. **音频格式与规格校验（`ffprobe`）**
   - 网易音乐人硬性门槛：**MP3 或 WAV 格式、音质 ≥ 320kbps、采样率 ≥ 44.1kHz、文件 < 200MB**。
   - 先用 `ffprobe` 检查源音频的 `codec_name`、`sample_rate`、`bit_rate`、`size`；若为 `.m4a`（如 Suno 导出的 Opus 138kbps）等不合规格式，经用户确认后用 `ffmpeg` 转为 48kHz / 16-bit 双声道 WAV：
     ```bash
     ffmpeg -y -i "<src>" -c:a pcm_s16le -ar 48000 -ac 2 "<dst.wav>"
     ```
2. **Suno 元数据与封面图自动联动**
   - 检查源音频元数据 `comment` 是否包含 `made with suno; ... id=<clip_id>`。
   - 若存在 `clip_id`，先调用 `suno` MCP 的 `audio-retrieve` 读取：
     - `metadata.lyrics`：若为 `[Instrumental]`，则语种选 **`纯音乐`**；
     - `metadata.style`：用于匹配曲风、情绪、场景标签及编写专辑简介；
     - `cover_image_large_url`：下载后用 `sips -g pixelWidth -g pixelHeight` 及 `read_file` 校验是否 ≥ 640×640（JPG/PNG）、方图、无乱码文字或水印；若不达标，建议使用即梦 `dreamina` CLI（`dreamina text2image --ratio=1:1 --resolution_type=2k`）或其他生图工具生成 ≥ 640×640 的 1:1 封面并截图核验。

---

## 3. 单条 CDP 长连接填表与已知避坑清单

> **核心定位规则**：严禁按页面中 `.ant-select` 的数组下标盲点！动态切换 `remix` / `是否AI作品` 会增删表单控件导致下标漂移；必须全部通过稳定的 **`[data-schemaform-field="..."]`** 属性定位。

1. **上传音频（`DOM.setFileInputFiles`）**
   - 精准匹配 `input[type="file"][accept*="audio"]`（注意区分封面与笔记图的 `accept="image/*"`），直接注入文件即可（Chrome 会原生派发 `input`/`change` 事件，勿重复手动派发以免二次上传）。
   - **进度轮询避坑**：仅监测歌曲条目容器内的 `正在上传`、`请等待音频上传完毕` 或进度条文本；**严禁全页正则匹配 `%`**，否则页面下方静态文案（`（发布私信、笔记预计为歌曲带来曝光+10%）`）会导致误判死等超时。
2. **新建专辑（`#albuminfobar` → `.albumform`）**
   - 展开下拉必须用 CDP `Input.dispatchMouseEvent`（`mousePressed` + `mouseReleased`）点击 `input.albuminfobar-input`（纯 DOM `.click()` 无法展开），再点击 `li[value="create"]` 展开 `.albumform`。
   - 向 `.albumform input[type="file"]` 注入封面后，等待 `.ant-modal`（「编辑封面」裁剪弹窗）出现并点击「保 存」，随后核验 `#albuminfobar` 顶部缩略图已刷新。
   - React 受控输入框（`专辑名称`、`专辑描述`、`歌曲名`、`站内笔记`）必须使用原生 `HTMLInputElement.prototype` / `HTMLTextAreaElement.prototype` 的 `value` setter 写入，并依次派发 `input`、`change`、`blur` 冒泡事件。
   - 填写 `albumType`（单曲选 `Single`）、`briefDesc`（10–2000 字）。
3. **歌曲表单字段映射（`form[data-msform-id="uploadProcessSongForm"]`）**
   - **`songTag`（歌曲类型）**：`原创` (`5`) / `翻唱` (`10`) / `remix` (`15`)。AI 改编/二创作品务必如实选 `remix` 或 `翻唱`，避免误选 `原创` 引发版权处罚。
   - **`originInfo`（采样来源，`remix` 时出现）**：搜索原曲并精准点击**原作者版本**（避免误选同名翻奏）。若需删除已有条目，点击「删除」后对 `.ant-popover:not(.ant-popover-hidden)` 中的「确 定」按钮直接调用 DOM `btn.click()`（避免 AntD 缩放动画期间坐标偏移）。
   - **特殊艺人名校验坑**：选中 `originInfo` 后，前端会自动在 `[data-schemaform-field="name"]`（歌曲名）前拼接 `原艺人-` 前缀；若点击「下一步」触发红字提示 `检测到输入内容包含特殊艺人名，建议您修改后再提交`，移除该前缀（原作者已规范保留在采样来源中）即可。
   - **`language`（语种）**：纯音乐选 `纯音乐`（`remix` + `纯音乐` 模式下，表单会以 `制作者` + `采样来源` 自动替代 `作词/作曲/编曲`）。
   - **`genre` / `tagInfoEmotion` / `tagInfoScene`**：通过对应 `[data-schemaform-field]` 展开 `.panel--2D7lO` 面板，先检查 `.panel-item.selected` 状态再点击，防止二次点击误反选。
   - **`aiTag`（是否 AI 作品）**：由 Suno 等 AI 工具生成时须如实选 `是`（`value="1"`），并在随后展开的下拉菜单中选择对应工具（如 `Suno AI`）。
   - **站内笔记必填坑**：页面底部 `.promotionSetting--QXIYF` 的「发布站内笔记」默认绑定曲目卡片且不可取消，留空点「下一步」会报错 `请完善宣发内容 / 请输入文案内容`；需填写简短得体的新歌介绍文案（如 `#歌名# 简介...`）。

---

## 4. 进度验收与强制安全停靠点

1. 提交第一步后，页面会先显示短暂的「加载中...」过渡态再跳转至第二步 **「收益设置（`.../incomeconfig`）」**；确认页面渲染完毕后点击「下一步」进入第三步 **「签约授权（`.../authorization`）」**。
2. **强制人工确认红线**：到达 `.../authorization` 签约授权页后，涉及《作品上传使用许可书》法律协议勾选及绑定手机号短信验证码，**必须立即暂停、通过 CDP 截图并使用 `read_file` 核验后报告给用户**。仅在用户明确确认同意协议并提供短信验证码后才可代填提交；严禁擅自签署多年期独家/非独家合约或尝试绕过短信验证。
