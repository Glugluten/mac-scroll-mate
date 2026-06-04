# Mac Scroll Mate / 自动反向 Mac 外接鼠标滚轮方向，并保持触控板控制逻辑不变

作为 Mac 用户，你是否每次连接鼠标外设时，都要手动切换滚轮方向（自然滚动开/关）？其本质是：触控板更像是在模拟你对一张真实纸面的滑动操作，而鼠标滚轮更像是在控制页面侧边的滑块。这两种交互隐喻天然相反，于是同一个“自然滚动”开关就很难同时照顾触控板和鼠标。这个小项目能够让 Mac 的自然滚动保持开启，让触控板维持熟悉的原生手感，同时在检测到你配置的鼠标时，只把鼠标滚轮事件反向。

As a Mac user, do you find yourself manually switching the scroll direction every time you connect an external mouse by turning Natural Scrolling on or off? The reason is that the trackpad behaves like you are sliding a real sheet of paper, while a mouse wheel behaves more like you are controlling the scrollbar on the side of a page. These two interaction models naturally point in opposite directions, so one Natural Scrolling switch cannot feel right for both devices at the same time. Mac Scroll Mate keeps Natural Scrolling enabled for the Mac trackpad, then reverses only the configured mouse wheel events when your mouse is connected.

Mac Scroll Mate is a small macOS LaunchAgent that keeps **Natural Scrolling** enabled globally and reverses only configured external mouse wheel events.

Mac Scroll Mate 是一个轻量级 macOS LaunchAgent，会让系统**自然滚动**保持开启，并只反向你配置的外接鼠标滚轮事件。

## 功能

- 系统自然滚动保持开启，触控板始终保留 Mac 原生自然滚动手感；连接指定鼠标时，只反向鼠标滚轮方向。
- 支持多个鼠标设备名，或 VendorID 和 ProductID 精确匹配设备。
- 基于 HID 设备事件和系统滚轮事件触发，空闲时基本不占用系统资源。

## Features

- Keeps Natural Scrolling enabled globally for the Mac trackpad, while reversing only the configured external mouse wheel direction.
- Supports multiple configured mouse device names, or exact `0xVID:0xPID` device matching.
- Triggered by HID device events and scroll wheel events, with minimal idle resource usage.

## Requirements / 系统要求

- macOS
- Xcode Command Line Tools
- Accessibility and Input Monitoring permission for the app

Install Command Line Tools if needed:

```sh
xcode-select --install
```

如未安装命令行工具，可运行：

```sh
xcode-select --install
```

安装后如果滚轮没有被反向，请到 **System Settings -> Privacy & Security**，分别在 **Accessibility** 和 **Input Monitoring** 中允许 `Mac Scroll Mate`。

After installation, if the mouse wheel is not reversed, open **System Settings -> Privacy & Security** and allow `Mac Scroll Mate` in both **Accessibility** and **Input Monitoring**.

If `Mac Scroll Mate` does not appear in the permission lists, run the installed app once with:

如果权限列表中没有出现 `Mac Scroll Mate`，可以运行一次已安装的程序来触发权限请求：

```sh
"$HOME/Library/Application Support/Mac Scroll Mate/Mac Scroll Mate.app/Contents/MacOS/Mac Scroll Mate" --request-permissions
```

## Configure Mouse Names / 配置鼠标名称

The app still needs a mouse allowlist because macOS scroll wheel events do not reliably expose the exact source device. The allowlist tells Mac Scroll Mate when it should reverse non-continuous wheel events.

程序仍然需要一份鼠标白名单，因为 macOS 的滚轮事件本身不能稳定提供具体来源设备。白名单用于告诉 Mac Scroll Mate：什么时候应该反向非连续滚轮事件。

1. Connect the mouse you want to detect.

   插上你想要检测的鼠标。

2. List connected HID devices:

   查看当前连接的 HID 设备：

```sh
hidutil list
```

3. Find the row for your mouse. Usually it has:

   找到你的鼠标对应的那一行。通常它会满足：

- `UsagePage` is `1`
- `Usage` is `2`
- `Built-In` is `0`

- `UsagePage` 为 `1`
- `Usage` 为 `2`
- `Built-In` 为 `0`

Example:

```txt
VendorID ProductID LocationID UsagePage Usage RegistryID  Transport Class              Product             UserClass                 Built-In
0x17ef   0x623a    0x1110000  1         2     0x100011e15 USB       AppleUserHIDDevice  Xiaoxin M2Pro 2.4G  AppleUserUSBHostHIDDevice 0
```

In this example, the mouse name is:

在这个例子里，鼠标名称是：

```txt
Xiaoxin M2Pro 2.4G
```

4. Add the mouse name to `mouse-names.txt`, one rule per line:

   将鼠标名称加入 `mouse-names.txt`，每行一条规则：

```txt
Xiaoxin M2Pro 2.4G
Logitech MX Master 3
```

Product names are matched exactly. For example, `MX Master` will not match `MX Master 3`.

产品名称使用精确匹配。例如，`MX Master` 不会匹配 `MX Master 3`。

You can also use an exact VendorID and ProductID pair:

也可以使用精确的 VendorID 和 ProductID 组合：

```txt
0x17ef:0x623a
```

Both formats can be mixed:

两种格式可以混用：

```txt
Xiaoxin M2Pro 2.4G
0x17ef:0x623a
Logitech MX Master 3
```

Only configured names or hardware IDs count as target mice. This avoids confusing wireless receivers, keyboards, or composite USB devices with the actual mouse.

只有配置文件里的设备名或硬件 ID 会被当作目标鼠标，这可以避免无线接收器、键盘或复合 USB 外设被误判。

Before installation, edit the repository file:

安装前，编辑仓库里的配置模板：

```sh
mouse-names.txt
```

After installation, the live config is copied to:

安装后，实际生效的配置文件位于：

```sh
~/Library/Application Support/Mac Scroll Mate/mouse-names.txt
```

If you edit the live config after installation, unplug and reconnect the mouse, or restart the LaunchAgent:

如果你在安装后修改实际生效的配置文件，可以拔插一次鼠标，或重启 LaunchAgent：

```sh
launchctl kickstart -k "gui/$(id -u)/com.glugluten.macscrollmate.agent"
```

## Install / 安装

Run:

运行：

```sh
./install.sh
```

The installer will:

安装脚本会：

- Build `Mac Scroll Mate`.
- Copy the app bundle to `~/Library/Application Support/Mac Scroll Mate/Mac Scroll Mate.app`.
- Copy `mouse-names.txt` on first install.
- Create a user LaunchAgent at `~/Library/LaunchAgents/com.glugluten.macscrollmate.agent.plist`.
- Start the LaunchAgent immediately.

## Check Status / 检查状态

Check whether the app process is running:

检查 app 进程是否正在运行：

```sh
pgrep -fl "Mac Scroll Mate"
```

Check whether the LaunchAgent is installed:

检查 LaunchAgent 是否已安装：

```sh
launchctl print "gui/$(id -u)/com.glugluten.macscrollmate.agent"
```

Run a local permission and mouse matching check:

运行本地权限和鼠标匹配检查：

```sh
./build.sh
./Mac\ Scroll\ Mate --check --config ./mouse-names.txt
```

After installation, you can also check the installed binary:

安装后，也可以检查已安装的二进制文件：

```sh
"$HOME/Library/Application Support/Mac Scroll Mate/Mac Scroll Mate.app/Contents/MacOS/Mac Scroll Mate" --check
```

Check the current Natural Scrolling preference:

检查当前自然滚动偏好值：

```sh
defaults read -g com.apple.swipescrolldirection
```

For this architecture, the value should stay `1` because the trackpad keeps Natural Scrolling enabled.

在当前架构下，这个值应当保持为 `1`，因为触控板会一直使用自然滚动。

## Uninstall / 卸载

Run:

运行：

```sh
./uninstall.sh
```

This stops the LaunchAgent and removes the installed app bundle and config.

该命令会停止 LaunchAgent，并移除已安装的 app bundle 和配置文件。

## How It Works / 工作原理

The app keeps macOS Natural Scrolling enabled globally. This preserves the native trackpad behavior.

程序会让 macOS 的自然滚动保持全局开启，因此触控板会维持系统原生手感。

It registers an `IOHIDManager` listener for mouse connect and disconnect events. When a device change arrives, it checks structured `hidutil list --ndjson` output against your configured product names or VendorID/ProductID pairs.

它通过 `IOHIDManager` 监听鼠标接入和拔出事件。设备变化发生后，程序会用结构化的 `hidutil list --ndjson` 输出和你的产品名称或 VendorID/ProductID 配置进行匹配。

When a configured mouse is connected, the app uses a `CGEventTap` to listen for scroll wheel events. Continuous scrolling events are treated as trackpad-like input and passed through. Non-continuous wheel events are replaced with newly created scroll events in the opposite direction.

当配置的鼠标处于连接状态时，程序会通过 `CGEventTap` 监听系统滚轮事件。连续滚动事件会被视作触控板一类的输入并直接放行；非连续滚轮事件会被替换成一个方向相反的新滚轮事件。

The private `setSwipeScrollDirection` function is still used, but only to keep Natural Scrolling enabled. The app no longer toggles Natural Scrolling off when a mouse is connected.

程序仍然会使用私有的 `setSwipeScrollDirection` 函数，但只用于确保自然滚动保持开启；连接鼠标时不再关闭系统自然滚动。

## Resource Usage / 资源占用

The app is event-driven and normally sleeps in the background. On the test machine, idle usage was approximately:

该程序是事件驱动的，平时在后台休眠。在测试机器上，空闲占用约为：

- CPU: `0.0%`
- Memory RSS: about `15 MB`

## Notes / 注意事项

- This tool uses a private macOS function and a `CGEventTap`. It works on the tested macOS version, but Apple may change related behavior in future releases.
- The LaunchAgent starts when the current user logs in, not during the early boot phase.
- If the app builds and detects your mouse but the wheel is not reversed, check Accessibility and Input Monitoring permissions first.

- 本工具使用了 macOS 私有函数和 `CGEventTap`。它在当前测试版本上可用，但 Apple 未来可能调整相关行为。
- LaunchAgent 会在当前用户登录后启动，不是在系统早期开机阶段启动。
- 如果程序能编译、也能检测到鼠标，但滚轮没有反向，请优先检查 Accessibility 和 Input Monitoring 权限。

## License / 许可证

This project is licensed under the MIT License. See `LICENSE` for details.

本项目使用 MIT License 授权，详情见 `LICENSE` 文件。
