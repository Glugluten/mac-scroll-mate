# Mac Scroll Mate / 自动切换 Mac 滚轮方向

作为 Mac 用户，你是否每次连接鼠标外设时，都要手动切换滚轮方向（自然滚动开/关）？其本质是：触控板更像是在模拟你对一张真实纸面的滑动操作，而鼠标滚轮更像是在控制页面侧边的滑块。这两种交互隐喻天然相反，于是同一个“自然滚动”开关就很难同时照顾触控板和鼠标。这个小项目能够在你连接指定鼠标时自动关闭自然滚动，在鼠标断开时自动开启自然滚动，让 Mac 在触控板和鼠标之间切换得更顺手。

As a Mac user, do you find yourself manually switching the scroll direction every time you connect an external mouse by turning Natural Scrolling on or off? The reason is that the trackpad behaves like you are sliding a real sheet of paper, while a mouse wheel behaves more like you are controlling the scrollbar on the side of a page. These two interaction models naturally point in opposite directions, so one Natural Scrolling switch cannot feel right for both devices at the same time. Mac Scroll Mate automatically turns Natural Scrolling off when your configured mouse is connected, and turns it back on when the mouse is disconnected.

Mac Scroll Mate is a small macOS LaunchAgent that automatically toggles **Natural Scrolling** based on whether your configured external mouse is connected.

Mac Scroll Mate 是一个轻量级 macOS LaunchAgent，可以根据你配置的外接鼠标是否连接，自动切换系统的**自然滚动**。

## 功能

- 外接鼠标连接时：关闭自然滚动，适合传统鼠标滚轮；外接鼠标断开时：开启自然滚动，适合 Mac 触控板。
- 支持多个鼠标设备名。
- 基于 HID 设备事件触发，基本不占用系统资源。

## Features

- External mouse connected: turns Natural Scrolling off for a traditional mouse wheel; external mouse disconnected: turns Natural Scrolling on for the Mac trackpad.
- Supports multiple configured mouse device names.
- Triggered by HID device events, with minimal system resource usage.

## Requirements / 系统要求

- macOS
- Xcode Command Line Tools

Install Command Line Tools if needed:

```sh
xcode-select --install
```

如未安装命令行工具，可运行：

```sh
xcode-select --install
```

## Configure Mouse Names / 配置鼠标名称

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

4. Add the mouse name to `mouse-names.txt`, one name per line:

   将鼠标名称加入 `mouse-names.txt`，每行一个名称：

```txt
Xiaoxin M2Pro 2.4G
Logitech MX Master 3
```

Only configured names count as external mice. This avoids confusing wireless receivers, keyboards, or composite USB devices with the actual mouse.

只有配置文件里的设备名会被当作外接鼠标，这可以避免无线接收器、键盘或复合 USB 外设被误判。

Before installation, edit the repository file:

安装前，编辑仓库里的配置模板：

```sh
mouse-names.txt
```

After installation, the live config is copied to:

安装后，实际生效的配置文件位于：

```sh
~/Library/Application Support/NaturalScrollAuto/mouse-names.txt
```

If you edit the live config after installation, unplug and reconnect the mouse, or restart the LaunchAgent:

如果你在安装后修改实际生效的配置文件，可以拔插一次鼠标，或重启 LaunchAgent：

```sh
launchctl kickstart -k "gui/$(id -u)/com.naturalscrollauto.agent"
```

## Install / 安装

Run:

运行：

```sh
./install.sh
```

The installer will:

安装脚本会：

- Build `NaturalScrollAuto` if needed.
- Copy the binary to `~/Library/Application Support/NaturalScrollAuto/`.
- Copy `mouse-names.txt` on first install.
- Create a user LaunchAgent at `~/Library/LaunchAgents/com.naturalscrollauto.agent.plist`.
- Start the LaunchAgent immediately.

## Uninstall / 卸载

Run:

运行：

```sh
./uninstall.sh
```

This stops the LaunchAgent and removes the installed binary and config.

该命令会停止 LaunchAgent，并移除已安装的二进制文件和配置文件。

## Check Status / 检查状态

Check whether the LaunchAgent is running:

检查后台任务是否正在运行：

```sh
launchctl print "gui/$(id -u)/com.naturalscrollauto.agent"
```

Check the current Natural Scrolling preference:

检查当前自然滚动偏好值：

```sh
defaults read -g com.apple.swipescrolldirection
```

- `1`: Natural Scrolling on / 自然滚动开启
- `0`: Natural Scrolling off / 自然滚动关闭

## How It Works / 工作原理

The app registers an `IOHIDManager` listener for mouse connect and disconnect events. When a relevant HID event arrives, it debounces the event burst, checks `hidutil list` against your configured mouse names, and applies the desired Natural Scrolling state.

程序通过 `IOHIDManager` 监听鼠标接入和拔出事件。收到相关 HID 事件后，它会合并短时间内的一组事件，再用 `hidutil list` 和你的鼠标名称配置进行匹配，最后应用对应的自然滚动状态。

To make the change actually affect active scrolling behavior, the app writes the user preference and calls macOS's private `setSwipeScrollDirection` function from `PreferencePanesSupport.framework`.

为了让修改真正影响当前滚动行为，程序会写入用户偏好，并调用 macOS 私有框架 `PreferencePanesSupport.framework` 中的 `setSwipeScrollDirection` 函数。

## Resource Usage / 资源占用

The app is event-driven and normally sleeps in the background. On the test machine, idle usage was approximately:

该程序是事件驱动的，平时在后台休眠。在测试机器上，空闲占用约为：

- CPU: `0.0%`
- Memory RSS: about `14 MB`

## Notes / 注意事项

- This tool uses a private macOS function. It works on the tested macOS version, but Apple may change private APIs in future releases.
- The LaunchAgent starts when the current user logs in, not during the early boot phase.
- If actual scrolling behavior does not update after a macOS upgrade, the private API call may need to be revisited.

- 本工具使用了 macOS 私有函数。它在当前测试版本上可用，但 Apple 未来可能调整私有 API。
- LaunchAgent 会在当前用户登录后启动，不是在系统早期开机阶段启动。
- 如果系统升级后按钮能变但实际滚动行为不生效，可能需要重新适配私有 API 调用。

## License / 许可证

This project is licensed under the MIT License. See `LICENSE` for details.

本项目使用 MIT License 授权，详情见 `LICENSE` 文件。
