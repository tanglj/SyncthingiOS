# Syncthing iOS

这是一个基于 SwiftUI 的 Syncthing iOS 客户端，参考了
`../syncthing-android` 的客户端组织方式，并直接使用 `../syncthing`
中的 Syncthing core 与 REST API。

当前目标是“嵌入 Syncthing core 的前台可用版”：应用在前台运行时启动
本机 Syncthing core，提供状态查看、Web GUI、共享文件浏览和 Markdown
文件编辑能力。

当前 App 显示名使用 `SyncCore`，避免与 Syncthing 官方客户端产生混淆。此项目
不是 Syncthing 官方产品。

## 当前功能

- 在应用前台运行内置 Syncthing core。
- 使用应用内本机 GUI/API 地址：`http://127.0.0.1:8384`。
- 读取 `/rest/system/status`、`/rest/system/version`、`/rest/config`、
  `/rest/system/connections` 等接口。
- 展示连接状态、文件夹、远程设备和本机 core 状态。
- 在应用内打开 Syncthing Web GUI。
- 可配置外部 Syncthing GUI/API 地址和 API Key。
- 浏览同步目录下的共享文件，行为接近系统“文件”应用。
- 支持 Markdown 文件预览和编辑。
- 在非顶层文件夹中创建文件夹或 Markdown 文件；新建文件会自动补 `.md`
  后缀。

暂不支持后台持续同步、App Store 权限审核流程和跨 App 直接写入其它应用
沙盒目录。

## 使用方式

### 使用内置 core

1. 打开应用，进入 `Settings`。
2. 在“内置核心”区域点击“启动”。
3. 启动成功后点击“使用本机核心 API”。
4. 回到首页查看连接状态、文件夹和远程设备。
5. 进入 `Files` 浏览 `Documents/Syncthing` 下的同步文件。

内置 core 的固定 API Key：

```text
ios-local-syncthing-core
```

### 连接外部 Syncthing

1. 打开目标 Syncthing 节点的 Web GUI。
2. 从 `Actions > Settings > GUI` 复制 API Key。
3. 在 iOS 应用中进入 `Settings`。
4. 填写 GUI 地址，例如局域网地址 `http://172.20.10.2:8384`，或远程
   HTTPS 地址。
5. 填写 API Key，点击“保存并连接”。

API Key 会保存到 Keychain。远程 Syncthing 建议使用 HTTPS；HTTP 主要用于
本机或局域网调试。

## 文件目录

内置 core 使用以下目录：

- core 数据目录：应用沙盒 `Application Support/SyncthingCore`
- 同步文件目录：应用沙盒 `Documents/Syncthing`

`Documents/Syncthing` 可通过 iOS“文件”应用访问。不要把同步目录指向
Obsidian 等其它 App 的沙盒目录，iOS 不允许当前应用直接写入其它应用沙盒。

## Markdown 编辑

Markdown 编辑器基于本地打包的 CodeMirror 资源：

- 预览资源：`SyncthingiOS/Resources/MarkdownPreview`
- 编辑资源：`SyncthingiOS/Resources/MarkdownEditor`

文件列表中点击 Markdown 文件会直接预览；点击文件行上的编辑按钮进入编辑。
编辑页顶部提供保存和取消。下拉关闭编辑页不会保存修改。

## 内置 Core

前台版的关键模块：

- Swift 生命周期管理：`SyncthingCoreManager`
- Go 桥接层：`../syncthing/mobile/ioscore`
- 本机 API Key：`ios-local-syncthing-core`
- 本机 GUI/API：`http://127.0.0.1:8384`

生成 iOS framework：

```bash
Scripts/build-ios-core.sh
```

脚本会输出：

```text
SyncthingiOS/Frameworks/Ioscore.xcframework
```

脚本会向 gomobile 构建注入 Syncthing 版本号，避免 Web GUI 版本字段显示
`unknown-dev`。重新生成 framework 后需要重新构建并安装 App。

## 构建验证

模拟器构建：

```bash
xcodebuild -project SyncthingiOS.xcodeproj \
  -scheme SyncthingiOS \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/syncthing-ios-sim \
  CODE_SIGNING_ALLOWED=NO build
```

真机构建：

```bash
xcodebuild -project SyncthingiOS.xcodeproj \
  -scheme SyncthingiOS \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/syncthing-ios-device \
  DEVELOPMENT_TEAM=<你的 Apple Team ID> \
  CODE_SIGN_STYLE=Automatic build
```

安装到当前测试 iPhone：

```bash
xcrun devicectl device install app \
  --device <设备 ID> \
  /private/tmp/syncthing-ios-device/Build/Products/Debug-iphoneos/SyncthingiOS.app
```

启动应用：

```bash
xcrun devicectl device process launch \
  --device <设备 ID> \
  --terminate-existing me.tanglj.SyncthingiOS
```

如果 iOS 首次启动被阻止，需要在系统设置中信任开发者证书：
`设置 > 通用 > VPN 与设备管理`。

## 开发说明

- 打开 `SyncthingiOS.xcodeproj`，运行 `SyncthingiOS` target。
- UI 主要使用 SwiftUI。
- Web GUI、Markdown 预览和 Markdown 编辑使用 WebKit。
- 底部菜单仍保留英文标题，其它应用界面文案使用中文。
- README 修改需保持中文。

