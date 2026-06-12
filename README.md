# Codex Task Light

`Codex Task Light` 是一个给 `Codex` 用的 macOS 菜单栏状态灯工具。
<img width="137" height="41" alt="截屏2026-06-12 23 44 27" src="https://github.com/user-attachments/assets/37e8b29b-e3ec-4a0f-b286-99d32b0272d4" />

它的作用是：

- 当 `Codex` 正在处理任务时，在菜单栏显示状态
- 当 `Codex` 完成任务时，立即给出反馈
- 当 `Codex` 报错或等待批准时，不用盯着窗口也能知道
- 即使关闭 `Codex` 窗口，只要 `Codex` 进程还在，状态灯仍然可见

菜单栏显示为一个纯色圆点：

- `🟢`
- `🟡`
- `🔴`
- `🔵`

## 状态规则

- `🟢`：空闲待机、任务完成，或任务被手动停止
- `🟡`：任务进行中，正在处理 prompt、调用工具、搜索、重连或继续执行
- `🔴`：任务执行出错
- `🔵`：`Codex` 正在等待权限批准

## 工作原理

这个项目由两部分组成：

1. `Codex Hooks`
   负责监听 `SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`PermissionRequest`、`Stop` 等生命周期事件。

2. `macOS 菜单栏应用`
   负责读取最新状态，并在菜单栏显示状态灯圆点。

整个流程如下：

1. `Codex` 触发 hook 事件
2. `scripts/hook_entry.py` 接收事件输入
3. `src/traffic_light_hook.py` 计算当前状态颜色
4. 状态写入 `.runtime/state.json`
5. 菜单栏程序 `CodexTrafficLight.app` 读取状态并更新显示

为了满足“打开 Codex 就自动看到状态灯”，项目还额外提供了一个 `launchd` 监视器：

- 它每隔几秒检查一次 `Codex` 进程
- 如果发现 `Codex` 已启动，但状态灯 app 没启动
- 就会自动拉起菜单栏状态灯

所以现在分成两层：

- `launchd` 负责“Codex 打开时自动启动状态灯”
- `Hooks` 负责“任务执行时实时更新颜色”

另外，顶部图标现在只显示一个圆点，不再显示 `CX` 文字，这样在菜单栏内容较多时更容易保留下来。

点击状态灯后，还可以在菜单里切换显示方式：

- `Menu Bar`
- `Floating Window`
- `Always on Top`

三种模式是单选关系，当前选择会写入 `./.runtime/preferences.json`，下次启动时自动恢复。

## 项目结构

- `.codex-plugin/plugin.json`：插件清单
- `hooks/hooks.json`：插件内 hooks 配置
- `hooks/global-hooks.json`：用户级全局 hooks 配置模板
- `scripts/hook_entry.py`：hook 入口脚本
- `src/traffic_light_hook.py`：状态判定逻辑
- `assets/CodexTrafficLight.swift`：菜单栏程序源码
- `scripts/build_menubar_app.sh`：构建菜单栏程序
- `scripts/ensure_cx_running.sh`：确保 `Codex` 启动时自动拉起 `CX`
- `assets/com.scott.codex-task-light.monitor.plist`：LaunchAgent 配置
- `tests/test_hook_logic.py`：状态逻辑测试

## 环境要求

- macOS
- 已安装 `Codex.app`
- 可用的 `python3`
- 可用的 `swiftc`

## 从 GitHub 开始的完整使用流程

### 1. 克隆仓库

```bash
git clone git@github.com:wsq547ak/codex-task-light.git
cd codex-task-light
```

如果你的仓库目录名不是 `codex-task-light`，下面所有命令里的当前目录 `$(pwd)` 都会自动适配，不需要手动改路径。

### 2. 一键安装

最推荐的安装方式：

```bash
./install.sh
```

它会自动完成这些事情：

- 构建菜单栏 app
- 生成并安装 `~/.codex/hooks.json`
- 生成并安装 `LaunchAgent`
- 重载自动启动监视器
- 重启状态灯 app

安装完成后，你只需要回到 `Codex` 里执行一次：

```text
/hooks
```

然后把指向当前仓库中 `scripts/hook_entry.py` 的 hook 项设为 `trust`。

### 3. 手动安装

如果你不想用一键脚本，也可以手动执行下面步骤。

### 3.1 构建菜单栏程序

```bash
./scripts/build_menubar_app.sh
```

构建完成后会生成：

```bash
./.runtime/CodexTrafficLight.app
```

### 3.2 生成并安装全局 Hooks

`Codex` 的全局 hooks 配置在：

```bash
~/.codex/hooks.json
```

由于 hook 命令需要写成绝对路径，仓库里的 `hooks/global-hooks.json` 只是模板。  
真正安装时，需要把当前 clone 目录路径写进去。

运行下面这段命令来生成最终配置：

```bash
python3 - <<'PY'
from pathlib import Path
import json

repo = Path.cwd()
template = repo / "hooks" / "global-hooks.json"
target = Path.home() / ".codex" / "hooks.json"

data = json.loads(template.read_text(encoding="utf-8"))

hook_command = f'/usr/bin/python3 {repo / "scripts" / "hook_entry.py"}'

for event_groups in data["hooks"].values():
    for group in event_groups:
        for hook in group["hooks"]:
            hook["command"] = hook_command

target.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"Wrote {target}")
PY
```

### 3.3 在 Codex 中信任 Hooks

`Codex` 对“新建或变更过的非托管 hooks”默认不会直接执行，必须先 trust。

你需要在 `Codex` 中执行：

```text
/hooks
```

然后把指向当前仓库中 `scripts/hook_entry.py` 的 hook 项全部设为 `trust`。

如果你刚 clone 下来，这个路径通常会是：

```text
<你的仓库绝对路径>/scripts/hook_entry.py
```

注意：

- 如果你输入 `/hooks` 没看到明显反应，通常是当前没有待审核的变更项，或者界面已经打开在侧栏/弹窗里
- 如果你修改了 hook 配置或路径，`Codex` 可能会要求重新 trust

### 3.4 安装自动启动监视器

如果你希望“只要打开 Codex，CX 就自动出现”，安装 `LaunchAgent`。

这一步同样需要把仓库绝对路径写进去，所以推荐用下面这组命令自动生成：

```bash
python3 - <<'PY'
from pathlib import Path

repo = Path.cwd()
template = (repo / "assets" / "com.scott.codex-task-light.monitor.plist").read_text(encoding="utf-8")

content = template.replace("__CODEX_TASK_LIGHT_ROOT__", str(repo))

target = Path.home() / "Library" / "LaunchAgents" / "com.scott.codex-task-light.monitor.plist"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(content, encoding="utf-8")
print(f"Wrote {target}")
PY

launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.scott.codex-task-light.monitor.plist"
launchctl kickstart -k "gui/$(id -u)/com.scott.codex-task-light.monitor"
```

安装完成后：

- 打开 `Codex`
- 等几秒
- 状态灯会自动出现在菜单栏

### 4. 日常使用

完成上面步骤后，日常使用流程就是：

1. 打开 `Codex`
2. 菜单栏自动出现状态灯
3. 在任意工作区开始任务
4. 状态灯根据任务状态自动变色

如果你切到了 `Floating Window` 或 `Always on Top`：

- 菜单栏圆点会隐藏
- 屏幕上会出现一个可拖动的小灯窗口
- 点击这个小灯窗口，也能弹出同一套菜单切换显示模式

## 推荐安装顺序

第一次使用，推荐按这个顺序来：

1. clone 仓库
2. 执行 `./install.sh`
3. 在 `Codex` 里 trust hooks
4. 测试状态变化

## 如何测试

可以用下面 5 种场景验证：

### 空闲状态

- 打开 `Codex`
- 不执行任务
- 菜单栏应显示 `🟢`

### 进行中状态

- 在任意项目里发起一个新任务
- 当 `Codex` 开始处理、调用工具或继续执行时
- 菜单栏应显示 `🟡`

### 报错状态

- 让任务执行到明显失败的工具调用
- 例如命令报错、脚本退出码非 `0`
- 菜单栏应显示 `🔴`

### 等待批准状态

- 触发一个需要人工批准的操作
- 当 `Codex` 停下来等待权限时
- 菜单栏应显示 `🔵`

### 手动停止状态

- 发起一个任务，确认灯变成 `🟡`
- 在任务执行过程中主动停止
- 菜单栏应切回 `🟢`

### 显示模式切换

- 点击当前状态灯
- 在 `Display Mode` 下选择 `Menu Bar`、`Floating Window` 或 `Always on Top`
- 选择后应立即切换到对应显示方式
- 重启 `Codex` 或状态灯 app 后，应恢复上次选择

## 当前实现细节

当前状态判定逻辑大致如下：

- `SessionStart` -> `绿色`
- `UserPromptSubmit` -> `黄色`
- `PreToolUse` -> `黄色`
- `PostToolUse`
  - 成功 -> `黄色`
  - 失败 -> `红色`
- `PermissionRequest` -> `蓝色`
- `Stop` -> `绿色`
- `task_started` 生命周期事件 -> `黄色`
- `task_complete` 生命周期事件 -> `绿色`
- `turn_aborted` 生命周期事件 -> `绿色`

当前实现不只看 hooks，还会额外读取 `~/.codex/sessions/.../*.jsonl` 里的生命周期事件来兜底，这样有两个好处：

- 任务真正开始时，更稳地切黄灯
- 用户手动停止时，也能从黄灯切回绿灯

显示层则支持 3 种单选模式：

- `Menu Bar`：显示在 macOS 菜单栏
- `Floating Window`：显示普通可拖动悬浮窗，可能被其他窗口遮住
- `Always on Top`：显示可拖动置顶悬浮窗，尽量保持在其他窗口上方

## 常见问题

### 1. 为什么打开 Codex 之后没有立刻看到状态灯？

先检查 3 件事：

1. 菜单栏 app 是否已经构建
2. `LaunchAgent` 是否已安装
3. `Codex` 是否已经启动几秒以上

如果还不出现，可以手动启动一次：

```bash
open ./.runtime/CodexTrafficLight.app
```

### 2. 为什么任务明明开始了，状态灯还是绿色？

通常是下面几种原因：

- `~/.codex/hooks.json` 还没更新到当前 clone 路径
- 新路径的 hooks 还没有重新 trust
- `Codex` 没有重启，仍在使用旧配置

建议顺序：

1. 确认 `~/.codex/hooks.json` 指向的是当前仓库路径
2. 重启 `Codex`
3. 再执行一次 `/hooks`
4. 重新 trust 新路径的 hook

### 3. 为什么 `/hooks` 看起来没反应？

可能是：

- 当前没有待审核的 hooks
- hooks 列表在 UI 里打开了，但没有明显跳转
- 你已经 trust 过当前 hash，所以没有新动作

如果你刚改过 hooks 路径或内容，最稳的是：

1. 重启 `Codex`
2. 再执行 `/hooks`
3. 查看是否出现需要 review 的项

### 4. 为什么关闭 Codex 窗口后，状态灯还在？

这是预期行为。

你的要求是：

- 只要 `Codex` 进程还在
- 即使关闭窗口
- 状态灯也继续显示

所以状态灯不依赖窗口，而依赖 `Codex` 进程和状态文件。

### 5. 为什么我手动停止后，之前一直是黄灯？

这个问题已经在当前版本修复。

现在手动停止不会只依赖 hook 的最后一条状态，而是会额外识别 Codex 会话里的 `turn_aborted` 事件，并切回 `🟢`。

### 6. 为什么状态栏很满时，灯可能会不明显？

当前版本已经把顶部显示改成“单独一个纯色圆点”，不再显示 `CX` 文本，目的是把占位压到最小。

需要说明的是：

- 这样可以显著提高可见性
- 但如果 macOS 菜单栏被系统级别严重挤压，任何第三方状态项仍可能被系统折叠
- 这已经是应用层面比较稳妥的做法

如果你经常录屏或菜单栏很拥挤，建议直接切到：

- `Floating Window`
- 或 `Always on Top`

## 开发与验证

运行测试：

```bash
python3 -m unittest discover -s tests
```

重新构建菜单栏程序：

```bash
./scripts/build_menubar_app.sh
```

重启菜单栏程序：

```bash
killall CodexTrafficLight || true
open ./.runtime/CodexTrafficLight.app
```

重新加载自动启动监视器：

```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.scott.codex-task-light.monitor.plist" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.scott.codex-task-light.monitor.plist"
launchctl kickstart -k "gui/$(id -u)/com.scott.codex-task-light.monitor"
```

## 设计说明

这个项目参考了 `edge-tts` 那种“轻入口脚本 + 明确核心逻辑”的组织思路：

- 入口薄
- 状态逻辑集中
- 可测试
- 不依赖额外 Python GUI 框架

不过需要说明：

- `edge-tts` 仓库本身并没有现成的 `Codex Hooks` 配置
- 这里参考的是它的项目组织方式，不是直接复用某个现成 hook 文件

## 适合谁用

这个项目适合：

- 经常让 `Codex` 在后台跑任务的人
- 不想一直盯着 `Codex` 窗口的人
- 同时开多个工作区，希望快速知道当前状态的人
- 想把 `Codex Hooks` 做成实际可感知工具的人
