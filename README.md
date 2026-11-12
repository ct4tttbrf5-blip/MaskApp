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

### 方式 A · 推荐：一键代跑（不需要打开 GitHub 网页建仓库）

**建仓库、推代码、盯 CI、下载 IPA 全部由脚本通过 `api.github.com` 完成**，既不用在浏览器里点「New repository」，也不用 `git push`（那个要连时通时断的 `github.com` 主站）。

1. 先拿授权。把 token **单独一行**写进 `D:\BaiduSyncdisk\dnjswork\APP\.maskapp-token`（该文件在仓库外，且已被 `.gitignore` 排除）：
   - **推荐（电脑网页打不开时用这个）**：用**手机浏览器**打开 `https://github.com/settings/tokens/new?scopes=repo,workflow&description=MaskApp`（建议用移动数据，别连同一个 WiFi），登录 → 过期选 7 天 → 生成 classic PAT → 把那串 `ghp_...` 发到电脑写进文件。电脑一次都不用打开 GitHub 网页。
   - 电脑网页能打开时，直接在电脑上做同样的事即可。
   - 备选：双击 `device-login.bat`，用手机输入屏幕上的 8 位验证码完成授权。注意这条通道仍要连 `github.com` 主站，国内链路时通时断，脚本会自动重试；反复连不上就改用上面的 PAT 方式。授权页显示应用名 `GitHub CLI`，是 GitHub 官方命令行工具的公开设备授权通道，正常。
2. 在工程目录执行（不带参数会自动使用 `<你的用户名>/MaskApp`，仓库不存在则自动创建为 Public）：

   ```bash
   python scripts/run_cloud_build.py
   ```

   也可指定：`python scripts/run_cloud_build.py my-repo` 或 `owner/repo`。
3. 脚本依次：验证身份 → 自动建仓库 → 通过 API 上传全部源码 → 等待云端 macOS 编译（约 5–10 分钟）→ 失败自动抓日志 → 成功后把 `MaskApp-unsigned.ipa` 下载到 `build-output/`。

> 按项目约定只跑一次 Release 构建，不分 LED / 激光模式分别编译。
> 构建失败时把脚本打印的报错发我，我改完你重跑同一条命令即可，本地不用装任何开发工具。
> 全部跑完后删除 `.maskapp-token`，并到 <https://github.com/settings/applications> 撤销授权。

### 方式 B · 手动推送（不需要 token）

先在 GitHub 网页新建**空仓库**（选 **Public**，公开仓库可免费用 macOS 构建机；**不要勾选** README / .gitignore / license，否则远端会多一次提交导致推送被拒）。然后双击 `push-to-github.bat`，或在 Git Bash 里执行 `bash push-to-github.sh`，粘贴仓库地址回车。

首次推送若弹出 GitHub 登录窗口，按提示用浏览器授权即可（Windows 一般自带 Git Credential Manager）。

推送后打开仓库 **Actions** 页 → 选 `Build unsigned IPA` → 点 **Run workflow**（推送本身也会自动触发）。流水线依次：安装 XcodeGen → 由 `project.yml` 生成 Xcode 工程 → 用 `xcodebuild` 编译未签名 Release 版 → 打包成 IPA → 上传为构建产物。

跑完在该次运行页面底部 **Artifacts** 下载 `MaskApp-unsigned-ipa`，解压得到 `MaskApp-unsigned.ipa`。

---

## 三、装到 iPhone（免费侧载，无需开发者账号）

用的是 AltStore，原理是用你的普通 Apple ID 在电脑上给 IPA 重新签名后安装。

### 电脑端准备（一次即可）

1. **先装 Apple 的驱动组件**（本机实测一个都没有，见下节）：到 <https://www.apple.com/itunes/download/win64> 下载 **官网安装版 iTunes** 并安装，完成后重启一次电脑。注意：**不要用 Microsoft Store 版**，它缺少 AltServer 依赖的 `Apple Mobile Device Service` / `Bonjour` 后台服务。官网安装版会一并装上这两个服务。若已改用「Apple Devices」App 且 AltServer 能识别手机，可跳过 iTunes。
2. 到 <https://altstore.io> 下载 **AltServer for Windows** 并安装。
3. 按下一节把数据线连好、在手机上点「信任此电脑」，确认电脑已经认出手机。
4. 运行 AltServer（出现在右下角托盘图标，**右键 → 以管理员身份运行**更稳）→ 点图标 → **Install AltStore** → 选你的 iPhone → 输入**用于签名**的 Apple ID 与密码（建议专门注册一个小号，原因见下）。
5. 手机上打开「设置 → 通用 → VPN 与设备管理」，点开**用于签名的那个 Apple ID**，选「信任」。

### 数据线连接：从插线到电脑认出手机

**① 先看用哪根线** —— 两头接口要对得上，而且必须是**能传数据的线**（有些便宜线只能充电，插上永远没反应，原装线最稳）：

| 手机型号 | 手机这头 | 电脑这头 |
| --- | --- | --- |
| iPhone 14 及更早 | Lightning（扁的小口） | USB-A（大口）或 USB-C，看电脑有什么口 |
| iPhone 15 及以后 | USB-C | USB-C，或用 USB-C 转 USB-A 的线 |

**② 插电脑的位置**：插**主机后面板 / 笔记本自带的 USB 口**，不要插 USB 分线器（Hub）、显示器上的口、键盘上的口、充电头。插到底，别松。

**③ 手机上必须做的动作**：把手机**解锁、亮屏、停在主屏幕**，几秒后会弹出「要信任此电脑吗？」→ 点 **信任** → 输入锁屏密码。这一步没做，电脑就只能看到「在充电」，看不到设备。

**④ 在电脑上确认连上了**（任选一个）：
- 打开 iTunes 或「Apple Devices」App，左侧/顶部出现手机小图标 ✅
- 右键开始菜单 → **设备管理器** → 「便携设备」或「通用串行总线设备」下出现 `Apple iPhone` / `Apple Mobile Device USB Driver`，且没有黄色感叹号 ✅
- 「此电脑」里出现 iPhone，能点进去看到照片文件夹 ✅

三个都没有 → 说明还没连上，按下面的表排查，先别急着开 AltServer。

| 现象 | 处理 |
| --- | --- |
| 只充电、电脑毫无反应 | 换一根**确定能传数据**的原装线；换一个 USB 口；别用 Hub |
| 不弹「信任此电脑」 | 保持手机解锁亮屏 → 拔下重插 → 还不行就重启手机和电脑；曾误点过「不信任」的话，到「设置 → 通用 → 传输或还原 iPhone → 还原 → 还原位置与隐私」后重插 |
| 设备管理器有黄色感叹号 | 右键该设备 → 更新驱动程序 → 自动搜索；或重装官网版 iTunes 后重启电脑 |
| iTunes 装了还是看不到 | `Win + R` 输入 `services.msc` → 找到 **Apple Mobile Device Service**，设为「自动」并点「启动」；Bonjour 服务同理 |
| AltServer 提示找不到设备 | 用管理员身份运行 AltServer；关闭电脑和手机上的 VPN；防火墙允许 AltServer；全程保持手机解锁亮屏并插着线 |

> 本机检测结果（2026-11-12）：未安装 iTunes / Apple Devices / Apple Mobile Device Service / Bonjour / AltServer，设备管理器里只有蓝牙配对残留，**没有任何 USB 连接的 iPhone 记录**。所以第 1 步的驱动组件在这台电脑上是必需的，不能跳过。
>
> 首次安装 AltStore **必须插线**；之后续签可以走同一 WiFi 无线完成。

### 关于 Apple ID：主号还是小号？

**不是必须，但建议单独用一个小号。** AltServer 要拿 Apple ID 和密码去向 Apple 申请免费开发证书，等于把账号凭据交给一个非 Apple 的桌面程序；而免费账号用于侧载偶尔会被风控、导致签名证书失效（社区有此类报告，AltStore 官方给出的解法通常就是换一个新 Apple ID，且没有已知的解封办法）。主号连着 iCloud 照片、购买记录、付款方式和家人共享，一旦受影响代价太大；小号废了重新注册一个即可。

只用主号也能装——风险是低概率但后果不对等。若图省事用主号，请务必开启双重认证，并且只在**官网下载的** AltServer 里输入。

**主号和小号可以同时存在，互不冲突**：

- 手机「设置 → 顶部你的名字」保持登录主号，**完全不用动**，iCloud / App Store / 微信等一切照旧；
- AltStore **App 内部**登录小号，仅用于签名。这是应用内账号，不是 iOS 系统级登录，不会把主号挤掉；
- 电脑 AltServer 里登录的必须和手机 AltStore 里的是**同一个小号**，否则续签会失败；
- 「VPN 与设备管理」里要信任的开发者证书属于小号，信任它不影响主号。

**注册小号（约 5 分钟）**：

1. 用浏览器打开 <https://account.apple.com> → 创建 Apple ID。**不要**在 iPhone「设置」里退出主号去登小号。
2. 准备一个没注册过 Apple ID 的邮箱（新开个 QQ / 163 / Outlook 最省事）、一个能收短信的手机号（通常可与主号相同，若提示已占用就换一个）、生日填成年、设置强密码。
3. 验证邮箱与手机号，开启双重认证。若 AltServer 反复拒绝登录，到 account.apple.com →「登录与安全」→「App 专用密码」生成一个专用密码填进去，比填主密码更稳妥。
4. 不绑银行卡、不充值，只在电脑 AltServer 和手机 AltStore 两处登录。首次可能要求同意免费的 Apple Developer 协议，同意即可。

> 免费账号最多同时激活 3 个侧载 App，而 AltStore 自己占 1 个，实际还能装 2 个。若要给多人用或省掉 7 天续签，就得换付费开发者账号 + TestFlight。

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
├── device-login.bat                ★ 网页打不开时，用手机验证码授权（Windows 双击）
├── push-to-github.bat              手动一键推送（Windows 双击）
├── push-to-github.sh               手动一键推送（Git Bash）
├── scripts/run_cloud_build.py      ★ 全自动：建仓库→推代码→盯 CI→下载 IPA
├── scripts/github_device_login.py  设备码授权（由 device-login.bat 调用）
├── scripts/make_icon.py            生成 App 图标（纯 Python 标准库）
├── build-output/                   编译完成后 IPA 存放位置
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

**Q：GitHub 网页打不开（ERR_CONNECTION_TIMED_OUT），怎么办？**

国内宽带到 GitHub 经常慢且抖动，Edge 会在默认超时内先放弃，但这不代表被封。实测同一台电脑用命令行请求 `github.com/new` 能拿到 HTTP 200，只是耗时 3–20 秒不等。按优先级试：

1. **最省事：电脑干脆不开网页**。用手机浏览器（移动数据）生成 PAT 写进 `.maskapp-token`，再跑 `python scripts/run_cloud_build.py`。建仓库、上传源码、盯 CI、下载 IPA 全走 `api.github.com`，这条链路实测稳定在 1 秒内；`github.com` 网页和 git 端点全程不碰。
2. 想让电脑也能开：换手机热点给电脑，或开 Edge 的 InPrivate 窗口重试几次；直接访问 `https://github.com/settings/tokens/new?scopes=repo,workflow&description=MaskApp` 这类深链接，比首页轻、更容易加载。
3. 关闭可能冲突的代理 / VPN 软件后重试。

脚本对慢链路加了超时和自动重试。另外按项目约定只跑一次 Release 构建，不分 LED / 激光模式分别编译。

**Q：能上 App Store 吗？**
能，但需要付费开发者账号和审核。工程本身是标准原生工程，满足条件后可直接 Archive 提交或走 TestFlight。

**Q：PWA / 网页版行不行？**
不行。iPhone 上的 Safari（以及所有 iOS 浏览器，都是 WebKit 内核）不支持 Web Bluetooth，网页应用无法连接 BLE 硬件。这也是必须做原生 App 的原因。

**Q：iOS 版本有要求吗？**
iOS 16.0 及以上，覆盖 iPhone 8 及之后的机型。
