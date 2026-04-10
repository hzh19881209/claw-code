# 在 Rocky Linux 9 安装和使用 Claw Code

本文面向 `Rocky Linux 9`，目标不是只把仓库编译出来，而是把它配置成一个可以像 `Claude Code` 那样参与项目开发的 CLI 工作流。

## 先说结论

- 仓库自带的 `install.sh` 在 `Rocky 9.6` 上可以运行，但它不是严格意义上的一键安装脚本。
- `install.sh` 只负责检查环境、构建仓库、做简单验证。
- 如果系统里没有 `rustc`、`cargo`，它会直接失败。
- 如果系统里缺少 `openssl-devel`、`pkg-config` 等构建依赖，也可能构建失败。
- 对 `Rocky Linux 9`，更适合使用本文附带的 `install-rocky9.sh`。

## 文件说明

- 一键安装脚本：`./install-rocky9.sh`
- 原仓库安装脚本：`./install.sh`
- 本说明文档：`./在RockyLinux9安装claw-code.md`

## 为什么 `install.sh` 不能算完整的一键安装

`install.sh` 的行为大致如下：

1. 检测当前系统是否是 `Linux`、`macOS` 或 `WSL`
2. 检查 `rustc`、`cargo`
3. 可选检查 `git`、`pkg-config`
4. 进入 `rust/` 工作区执行 `cargo build --workspace`
5. 用 `claw --version` 和 `claw --help` 做 smoke test

这意味着：

- 它支持 `Rocky 9.6` 这种 Linux 系统
- 但它不会自动安装 `Rust`
- 也不会自动用 `dnf` 安装 `gcc`、`openssl-devel`、`pkgconf-pkg-config`
- 所以在一台全新的 `Rocky 9.6` 主机上，通常不能直接无脑一次成功

## 推荐安装方式

### 方式一：直接使用一键脚本

在当前仓库目录执行：

```bash
chmod +x ./install-rocky9.sh
./install-rocky9.sh
```

默认行为：

- 仅允许在 `Rocky Linux 9` 上运行
- 自动安装构建依赖
- 自动安装 `rustup` 和稳定版 Rust
- 自动编译 `claw`
- 自动把二进制安装到 `~/.local/bin/claw`
- 自动把 `~/.local/bin` 加入 `~/.bashrc`

如果你想编译 debug 版：

```bash
./install-rocky9.sh --debug
```

如果你不想自动改 `~/.bashrc`：

```bash
./install-rocky9.sh --no-bashrc
```

如果你想装到自定义目录：

```bash
./install-rocky9.sh --install-dir "$HOME/bin"
```

### 方式二：手工安装

先装系统依赖：

```bash
sudo dnf update -y
sudo dnf install -y \
  git \
  curl \
  ca-certificates \
  gcc \
  gcc-c++ \
  make \
  cmake \
  pkgconf-pkg-config \
  openssl-devel \
  which \
  tar \
  unzip \
  tmux
```

安装 Rust：

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
rustc --version
cargo --version
```

编译：

```bash
cd /path/to/claw-code/rust
cargo build --workspace --release
```

安装到本地 PATH：

```bash
mkdir -p "$HOME/.local/bin"
install -m 0755 ./target/release/claw "$HOME/.local/bin/claw"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
source "$HOME/.bashrc"
claw --version
```

## 推荐的使用方式

如果你的目标是像 `Claude Code` 一样开发项目，不建议只把它当成一次性命令执行器，而是建议按下面的方式使用。

### 1. 在项目目录中启动

不要总站在 `claw-code` 这个仓库里运行它。你应该进入你自己的项目目录再启动：

```bash
cd /path/to/your/project
claw --permission-mode workspace-write --model qwen2.5-coder
```

推荐先做一次只读分析：

```bash
cd /path/to/your/project
claw --permission-mode read-only --model qwen2.5-coder
```

### 2. 先连接模型

`claw` 本身不是模型，它需要后端模型服务。

如果你在本机使用 `Ollama`：

```bash
export OPENAI_BASE_URL="http://127.0.0.1:11434/v1"
export OPENAI_API_KEY="local-dev-token"
```

如果你使用本地或内网里的 `vLLM` / `LM Studio` / 其他 OpenAI 兼容服务：

```bash
export OPENAI_BASE_URL="http://127.0.0.1:8000/v1"
export OPENAI_API_KEY="local-dev-token"
```

然后测试一下：

```bash
claw --model qwen2.5-coder prompt "reply with the word ready"
```

### 3. 用 REPL 而不是只用单次 prompt

最接近 `Claude Code` 工作方式的是进入交互模式：

```bash
cd /path/to/your/project
claw --permission-mode workspace-write --model qwen2.5-coder
```

进入后建议先执行：

```text
/doctor
/status
/permissions
```

然后按任务来驱动：

```text
请先阅读当前仓库结构，告诉我入口文件和核心模块
请定位认证逻辑相关代码
请先给出修改计划，不要直接改
开始修改，并在修改后运行相关测试
请总结变更内容
```

### 4. 会话恢复

`claw` 会把会话保存在当前项目的 `.claw/sessions/` 下。

下次可以直接恢复：

```bash
cd /path/to/your/project
claw --resume latest
```

### 5. 推荐和 `tmux` 一起用

在 Rocky Linux 上，最实用的方式是：

```bash
cd /path/to/your/project
tmux new -s dev
claw --permission-mode workspace-write --model qwen2.5-coder
```

这样 SSH 断开后会话也不容易丢。

## 推荐权限策略

建议不要长期默认使用最高权限。

### 只读审查

```bash
claw --permission-mode read-only --model qwen2.5-coder
```

适合：

- 看代码
- 查结构
- 做 review
- 查 bug

### 项目内改动

```bash
claw --permission-mode workspace-write --model qwen2.5-coder
```

适合：

- 修改当前项目文件
- 写测试
- 调整配置

### 不建议长期默认使用

```bash
claw --permission-mode danger-full-access
```

只有在你明确知道自己在做什么时才考虑。

## 建议的项目本地配置

在你的项目根目录创建：

```text
.claw/settings.local.json
```

示例内容：

```json
{
  "model": "qwen2.5-coder",
  "telemetry": false,
  "permissions": {
    "defaultMode": "workspace-write"
  }
}
```

如果你只想做只读分析，把 `workspace-write` 改成 `read-only`。

## 一个完整的日常工作流示例

```bash
cd ~/workspace/my-project
tmux attach -t dev || tmux new -s dev
export OPENAI_BASE_URL="http://127.0.0.1:11434/v1"
export OPENAI_API_KEY="local-dev-token"
claw --permission-mode workspace-write --model qwen2.5-coder
```

进入后：

```text
/doctor
/status
请阅读当前仓库并总结模块边界
请检查 auth 模块是否存在明显 bug
请提出最小修复方案
开始修改，并运行相关测试
请输出本次变更摘要
/diff
```

## 故障排查

### `cargo: command not found`

说明 Rust 没装好或当前 shell 没加载环境：

```bash
source "$HOME/.cargo/env"
```

### 构建时报 OpenSSL 或 pkg-config 相关错误

检查这些包是否安装：

```bash
sudo dnf install -y openssl-devel pkgconf-pkg-config gcc gcc-c++
```

### `claw: command not found`

重新加载 shell：

```bash
source "$HOME/.bashrc"
```

或者直接执行：

```bash
~/.local/bin/claw --version
```

### 本地模型连接失败

检查环境变量和服务监听地址：

```bash
echo "$OPENAI_BASE_URL"
echo "$OPENAI_API_KEY"
curl http://127.0.0.1:11434/v1/models
```

## 最后的建议

- 如果你是长期主力开发，优先选择 `Rocky Linux 9`
- 使用 `tmux + claw + 本地 OpenAI 兼容模型服务`
- 默认先用 `read-only` 或 `workspace-write`
- 进入具体项目目录后再启动 `claw`
- 把它当成长期会话式开发助手，而不是只执行一次 prompt
