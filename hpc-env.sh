#!/bin/sh

if [ -z "${USER:-}" ]; then
  USER="$(id -un 2>/dev/null || true)"
  if [ -n "$USER" ]; then
    export USER
  fi
fi

# Derive HOME from account information if not already set.
if [ -z "${HOME:-}" ] && [ -n "${USER:-}" ]; then
  USER_HOME="$(getent passwd "$USER" | cut -d: -f6)"
  if [ -n "$USER_HOME" ]; then
    export HOME="$USER_HOME"
  fi
fi

# Per-user scratch path for temporary data and job outputs.
if [ -n "${USER:-}" ]; then
  export SCRATCH="/scratch/$USER"
elif [ -n "${LOGNAME:-}" ]; then
  export SCRATCH="/scratch/$LOGNAME"
fi

# Lazily create private scratch directory when possible.
if [ -n "${SCRATCH:-}" ] && [ ! -d "$SCRATCH" ] && [ -w /scratch ]; then
  mkdir -p "$SCRATCH" 2>/dev/null || true
  chmod 700 "$SCRATCH" 2>/dev/null || true
fi
