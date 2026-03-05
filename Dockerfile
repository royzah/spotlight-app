# ──────────────────────────────────────────────────────────────
# TrustSky Spotlight — Android build container
# Produces debug APK or release AAB without local Android SDK.
#
#   docker compose run android-build          # debug APK
#   docker compose run android-release        # release AAB
# ──────────────────────────────────────────────────────────────

FROM node:20-slim AS base

# Avoid prompts during package installs
ENV DEBIAN_FRONTEND=noninteractive

# Install JDK 17 + basic tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jdk-headless \
    wget \
    unzip \
    git \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# ── Android SDK ──────────────────────────────────────────────
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=${ANDROID_HOME}
ENV PATH=${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools

RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/cmdtools.zip && \
    unzip -q /tmp/cmdtools.zip -d ${ANDROID_HOME}/cmdline-tools && \
    mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest && \
    rm /tmp/cmdtools.zip

# Accept licenses and install SDK components
RUN yes | sdkmanager --licenses > /dev/null 2>&1 && \
    sdkmanager \
      "platform-tools" \
      "platforms;android-35" \
      "platforms;android-36" \
      "build-tools;36.0.0" \
      "build-tools;35.0.0"

# ── Project setup ────────────────────────────────────────────
WORKDIR /app

# Copy package files first for better layer caching
COPY package.json package-lock.json ./
RUN npm ci

# Copy remaining project files
COPY . .

# ── Build targets ────────────────────────────────────────────

# Debug APK
FROM base AS build-debug
RUN npx cap sync android
WORKDIR /app/android
RUN ./gradlew assembleDebug --no-daemon
# Output: /app/android/app/build/outputs/apk/debug/app-debug.apk

# Release AAB (unsigned — sign in CI or with Fastlane)
FROM base AS build-release
RUN npx cap sync android
WORKDIR /app/android
RUN ./gradlew bundleRelease --no-daemon
# Output: /app/android/app/build/outputs/bundle/release/app-release.aab

# Default target: debug
FROM build-debug
