#pragma once

#include <Arduino.h>

#define VK_FIRMWARE_PROJECT "esp-velux-kli2mqtt"
#define VK_FIRMWARE_VERSION "0.1.2"

constexpr uint8_t kOpenPin = D5;
constexpr uint8_t kStopPin = D6;
constexpr uint8_t kClosePin = D7;
constexpr uint16_t kButtonPressMs = 200;
constexpr uint16_t kCommandCooldownMs = 700;
constexpr uint32_t kWifiRetryMs = 10000;
constexpr uint32_t kMqttRetryMs = 5000;
constexpr uint32_t kOtaWindowMs = 60000;

#if __has_include("secrets.h")
#include "secrets.h"
#else
#include "secrets.example.h"
#define VK_CONFIG_PLACEHOLDER 1
#endif
