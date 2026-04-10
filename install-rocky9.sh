#!/usr/bin/env bash

set -euo pipefail

BUILD_PROFILE="release"
INSTALL_DIR="${HOME}/.local/bin"
UPDATE_BASHRC="1"

print_usage() {
    cat <<'EOF'
Usage: ./install-rocky9.sh [options]

Options:
  --debug            Build the debug profile instead of release.
  --release          Build the release profile (default).
  --install-dir DIR  Install the claw binary into DIR.
  --no-bashrc        Do not add the install dir to ~/.bashrc.
  -h, --help         Show this help text and exit.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --debug)
            BUILD_PROFILE="debug"
            ;;
        --release)
            BUILD_PROFILE="release"
            ;;
        --install-dir)
            shift
            if [ "$#" -eq 0 ]; then
                echo "error: missing value for --install-dir" >&2
                exit 2
            fi
            INSTALL_DIR="$1"
            ;;
        --no-bashrc)
            UPDATE_BASHRC="0"
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            print_usage >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$(uname -s)" != "Linux" ]; then
    echo "error: this installer only supports Rocky Linux 9 on Linux." >&2
    exit 1
fi

if [ ! -r /etc/os-release ]; then
    echo "error: cannot read /etc/os-release to verify the operating system." >&2
    exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

if [ "${ID:-}" != "rocky" ]; then
    echo "error: detected ID=${ID:-unknown}; this script is intended for Rocky Linux 9." >&2
    exit 1
fi

case "${VERSION_ID:-}" in
    9|9.*) ;;
    *)
        echo "error: detected VERSION_ID=${VERSION_ID:-unknown}; this script is intended for Rocky Linux 9." >&2
        exit 1
        ;;
esac

if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
elif [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    echo "error: sudo is required when not running as root." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUST_DIR="${SCRIPT_DIR}/rust"

if [ ! -f "${RUST_DIR}/Cargo.toml" ]; then
    echo "error: rust workspace not found at ${RUST_DIR}" >&2
    exit 1
fi

echo "[1/6] Installing Rocky Linux build dependencies"
${SUDO} dnf install -y \
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

echo "[2/6] Installing or updating Rust toolchain"
if ! command -v cargo >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

if [ -f "${HOME}/.cargo/env" ]; then
    # shellcheck disable=SC1090
    source "${HOME}/.cargo/env"
fi

if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo is still unavailable after rustup installation." >&2
    exit 1
fi

rustup toolchain install stable >/dev/null
rustup default stable >/dev/null

echo "[3/6] Building claw (${BUILD_PROFILE})"
pushd "${RUST_DIR}" >/dev/null
if [ "${BUILD_PROFILE}" = "release" ]; then
    cargo build --workspace --release
    CLAW_BIN="${RUST_DIR}/target/release/claw"
else
    cargo build --workspace
    CLAW_BIN="${RUST_DIR}/target/debug/claw"
fi
popd >/dev/null

if [ ! -x "${CLAW_BIN}" ]; then
    echo "error: expected binary not found at ${CLAW_BIN}" >&2
    exit 1
fi

echo "[4/6] Installing binary into ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
install -m 0755 "${CLAW_BIN}" "${INSTALL_DIR}/claw"

echo "[5/6] Updating shell PATH configuration"
if [ "${UPDATE_BASHRC}" = "1" ]; then
    mkdir -p "${HOME}/.local/bin"
    PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
    if [ -f "${HOME}/.bashrc" ]; then
        if ! grep -Fqx "${PATH_LINE}" "${HOME}/.bashrc"; then
            printf '\n%s\n' "${PATH_LINE}" >> "${HOME}/.bashrc"
        fi
    else
        printf '%s\n' "${PATH_LINE}" > "${HOME}/.bashrc"
    fi
fi

export PATH="${INSTALL_DIR}:${PATH}"

echo "[6/6] Verifying installation"
"${INSTALL_DIR}/claw" --version
"${INSTALL_DIR}/claw" --help >/dev/null

cat <<EOF

Install complete.

Binary:
  ${INSTALL_DIR}/claw

Recommended next steps:
  1. Reload your shell:
       source "${HOME}/.bashrc"

  2. Configure a local OpenAI-compatible model endpoint, for example:
       export OPENAI_BASE_URL="http://127.0.0.1:11434/v1"
       export OPENAI_API_KEY="local-dev-token"

  3. Start claw inside a project directory:
       cd /path/to/your/project
       claw --permission-mode workspace-write --model qwen2.5-coder

  4. In the REPL, run:
       /doctor
       /status

If you prefer a quick read-only audit first, use:
  claw --permission-mode read-only prompt "summarize this repository"
EOF
