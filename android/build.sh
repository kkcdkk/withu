#!/bin/bash
# 에이전트/CI 공용 빌드 헬퍼 — JDK 21 고정 후 gradle 실행.
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export ANDROID_HOME=$HOME/Library/Android/sdk
cd "$(dirname "$0")"
exec ./gradlew "$@"
