# 电子面膜 3.0 · iPhone 控制端

一个 SwiftUI 原生 iOS App，通过蓝牙连接并控制电子面膜 3.0：模式切换、档位、护理时长、倒计时自动停止、使用记录。

当前状态：**代码完整，BLE 协议为占位值**，可先用内置的演示模式跑通全部界面与交互，不需要真实硬件。

工程已经是一个初始化好的本地 Git 仓库（首次提交已完成），源码与配置也已做过编译前验证：

- 10 个 Swift 文件经 Swift 语法解析器（tree-sitter-swift）解析，**0 语法错误**
- `Info.plist` 可被正确解析（16 个键），`Assets.xcassets` 的 `Contents.json` 均为合法 JSON
- `project.yml` 与 `build-ipa.yml` 均为合法 YAML，字段已按 XcodeGen / GitHub Actions 规范核对
- 界面预览页 29 处 DOM 引用全部有对应元素，脚本括号配对通过

注意：以上是**语法与配置级**验证。类型检查、链接和真机编译只能在 macOS 的 Xcode 里完成，走下面的云端流程；Swift 代码目前尚未经过 Xcode 编译。

---

## 一、先看界面（不需要任何工具）

直接双击打开 `preview/index.html`，里面是四个页面的高保真预览，可以点模式、档位、时长和底部导航。这一步只是看外观，不是 App 本体。

---

## 二、把工程编译成安装包

苹果规定 iOS App 必须在 macOS + Xcode 上编译，Windows 做不到。所以编译交给 GitHub 的云端 macOS 构建机完成。

### 1. 建仓库并推送

在 GitHub 新建一个**空仓库**（建议选 **Public**，公开仓库可免费使用 macOS 构建机；私有仓库的 macOS 分钟数按 10 倍计费）。**不要勾选 README / .gitignore / license**，否则远端会多出一次提交导致推送被拒。

**最省事**：双击 `push-to-github.bat`，或在 Git Bash 里执行 `bash push-to-github.sh`。粘贴仓库地址回车，脚本会自动配置远端、推送，并打开 Actions 页面。

手动方式：

```bash
cd D:/BaiduSyncdisk/dnjswork/APP/MaskApp
git remote add origin https://github.com/<你的用户名>/MaskApp.git
git push -u origin main
```

首次推送若弹出 GitHub 登录窗口，按提示用浏览器授权即可（Windows 一般自带 Git Credential Manager）。

### 2. 触发构建

打开仓库的 **Actions** 页 → 左侧选 `Build unsigned IPA` → 点 **Run workflow**（推送代码时也会自动触发）。

流水线会依次：安装 XcodeGen → 由 `project.yml` 生成 Xcode 工程 → 用 `xcodebuild` 编译未签名 Release 版 → 打包成 `MaskApp-unsigned.ipa` → 上传为构建产物。

约 5–10 分钟。跑完后在该次运行页面底部 **Artifacts** 下载 `MaskApp-unsigned-ipa`，解压得到 `MaskApp-unsigned.ipa`。

> 如果构建失败，把 Actions 里的报错日志发我，我照着改。改完重新 push 即可，不需要你本地装任何开发工具。

---

## 三、装到 iPhone（免费侧载，无需开发者账号）

用的是 AltStore，原理是用你的普通 Apple ID 在电脑上给 IPA 重新签名后安装。

### 电脑端准备（一次即可）

1. 到 <https://altstore.io> 下载 **AltServer for Windows** 并安装。
2. 如果安装或连接时提示缺少组件，去 Apple 官网下载安装版 **iTunes**（注意：**不要用 Microsoft Store 版**，它缺驱动）；新版系统若已能识别设备可跳过。
3. 用数据线连接 iPhone，手机上点「信任此电脑」。
4. 运行 AltServer（出现在右下角托盘图标）→ 点图标 → **Install AltStore** → 选你的 iPhone → 输入 Apple ID 与密码（建议专门注册一个小号，别用主账号）。
5. 手机上打开「设置 → 通用 → VPN 与设备管理」，点开你的 Apple ID，选「信任」。

### 安装 App

1. 把 `MaskApp-unsigned.ipa` 传到手机（微信文件传输助手、邮件附件、存进「文件」App 都行）。
2. 打开手机上的 AltStore，用**同一个 Apple ID** 登录。
3. 底部 `My Apps` → 左上角 `+` → 从文件列表里选这个 IPA。
4. AltStore 会自动签名并安装，桌面上出现「电子面膜」图标。

### 关于 7 天续签（免费方案的唯一麻烦）

免费 Apple ID 签发的证书**只有 7 天有效期**，过期后 App 会打不开（数据不会丢）。

- AltServer 在电脑上运行、且手机与电脑处于**同一 WiFi** 时，AltStore 会在后台自动续签，日常基本无感。
- 若连续 7 天没连过这台电脑，重新用数据线连一次、在 AltStore 里点 `Refresh All` 即可。
- 免费账号还有「最多 2 台设备 / 3 个侧载 App」的限制，够自己用，不适合批量分发。

> 如果以后要给客户用或上架 App Store，就需要 Apple Developer Program（¥688/年）+ TestFlight，届时我再补一份带签名的 workflow，工程源码不用改。

---

## 四、接入真实电子面膜 3.0

**只需要改一个文件：`MaskApp/BLEConfig.swift`。** 其余代码都不用动。

需要填的东西：

| 项目 | 说明 |
| --- | --- |
| `advertisedNamePrefix` | 设备广播名前缀，用于过滤 |
| `serviceUUID` / `writeUUID` / `notifyUUID` | 主服务、写特征、通知特征 UUID |
| `makeFrame` | 帧格式（帧头、长度、校验、帧尾） |
| `setMode` / `setIntensity` / `setDuration` / `start` / `stop` | 各指令的操作码与数据字节 |
| `parseStatus` | 设备状态上报的解析规则 |
| `maxPacketSize` | 单次写入上限，超出会自动分片 |

**不知道 UUID 怎么办**：在「设置」里关掉演示模式、打开「显示周边全部 BLE 设备」，回「设备」页扫描并连接真机。App 会把发现的**全部服务 UUID 和特征 UUID**打印到「设置 → 蓝牙调试日志」里，照抄进 `BLEConfig.swift` 即可。日志同时会显示每次下发的原始十六进制指令和收到的状态数据，方便和固件逐字节对。

在拿到准确协议前，代码里已经做了两处兜底，方便首次调试：

- 占位 UUID 匹配不上时，会**自动挑一个可写特征和一个通知特征**临时连通，并记进日志；
- 状态数据格式不匹配时只记日志、不崩溃，界面显示「等待状态上报」。

**关于 LED / 激光模式**：按项目约定，固件统一只按 LED 模式编译一遍。如果首版 App 不需要激光入口，把 `BLEConfig.showLaserMode` 改成 `false`，界面会自动只剩一个模式卡片，不用改任何界面代码。

---

## 五、工程结构

```
MaskApp/
├── README.md                       本文件
├── project.yml                     XcodeGen 工程定义（CI 里生成 .xcodeproj）
├── .github/workflows/build-ipa.yml 云端编译出未签名 IPA
├── .gitignore
├── push-to-github.bat              一键推送（Windows 双击）
├── push-to-github.sh               一键推送（Git Bash）
├── scripts/make_icon.py            生成 App 图标（纯 Python 标准库）
├── preview/index.html              界面预览，Windows 双击即可看
└── MaskApp/                        Swift 源码
    ├── MaskAppApp.swift            入口
    ├── RootView.swift              四个 Tab
    ├── Theme.swift                 配色与卡片样式
    ├── BLEConfig.swift             ★ 唯一需要按固件协议修改的文件
    ├── BluetoothManager.swift      CoreBluetooth 扫描/连接/重连/收发/演示模式
    ├── SessionController.swift     护理会话、倒计时、自动停止、记录持久化
    ├── DeviceView.swift            设备页
    ├── ControlView.swift           护理控制页
    ├── HistoryView.swift           使用记录页
    ├── SettingsView.swift          设置与调试日志
    ├── Info.plist                  蓝牙权限与后台模式
    └── Assets.xcassets/            图标与主题色
```

技术参数：iOS 16.0+，Swift 5.9，SwiftUI + CoreBluetooth，无第三方依赖。

---

## 六、演示模式

默认关闭，可在「设置」里打开。打开后：

- 不调用真实蓝牙，虚拟出两台「DN-MASK-3.0（演示）」设备；
- 连接后模式、档位、时长、开始/停止、倒计时、电量、使用记录全部可走通；
- 下发的指令和回传的状态帧走的是**和真机完全相同的编解码逻辑**，所以协议代码可以先验证；
- 状态帧每秒刷新一次，倒计时会真实走动，结束会自动写入一条记录。

---

## 七、常见问题

**Q：为什么不直接给我一个能双击安装的 IPA？**
苹果的签名机制不允许。IPA 必须用你的 Apple ID 证书签名才能装到你的手机上，这一步只能在你的电脑 + 你的账号下完成。云端编译只能产出未签名包。

**Q：能上 App Store 吗？**
能，但需要付费开发者账号和审核。工程本身是标准原生工程，满足条件后可直接 Archive 提交或走 TestFlight。

**Q：PWA / 网页版行不行？**
不行。iPhone 上的 Safari（以及所有 iOS 浏览器，都是 WebKit 内核）不支持 Web Bluetooth，网页应用无法连接 BLE 硬件。这也是必须做原生 App 的原因。

**Q：iOS 版本有要求吗？**
iOS 16.0 及以上，覆盖 iPhone 8 及之后的机型。
