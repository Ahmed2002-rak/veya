/*
 * VEYA ESP32 Bluetooth-Classic SPP Sample
 *
 * Minimal Arduino sketch for ESP32 with Bluetooth-Classic SPP server.
 * Sends hardcoded telemetry frames over BT at 10 Hz to the VEYA Raspberry Pi.
 *
 * Requirements:
 * - ESP32 board + Arduino IDE
 * - Espressif Arduino core 2.x+ (BluetoothSerial is built-in)
 * - Standard ESP32 (not C3/S2/S3 which lack BT-Classic)
 */

#include <BluetoothSerial.h>
#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_bt_device.h"
#include "esp_gap_bt_api.h"
#include "esp_bt_defs.h"

BluetoothSerial SerialBT;

unsigned long lastTelemetryMs = 0;
const unsigned long TELEMETRY_INTERVAL_MS = 100;  // 10 Hz
bool clientConnected = false;
bool helloSent = false;

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\nVEYA ESP32 sample — BT-Classic SPP server starting");

  // Set Class of Device so modern bluez (5.66+) sees the ESP32 in scan on listings.
  // Without a non-zero CoD, bluez filters the device from its D-Bus cache and
  // pair operations fail with "Device not available" even though hcitool sees it.
  esp_bt_cod_t cod;
  cod.major = ESP_BT_COD_MAJOR_DEV_AV;
  cod.minor = 0;
  cod.service = 0;
  esp_bt_gap_set_cod(cod, ESP_BT_SET_COD_MAJOR_MINOR);

  // false = slave/server mode (explicit); starts BT-Classic SPP, not BLE
  SerialBT.begin("VEYA-OBD-SAMPLE", false);

  // Make device connectable and generally discoverable for bluez inquiry scans
  esp_bt_gap_set_scan_mode(ESP_BT_CONNECTABLE, ESP_BT_GENERAL_DISCOVERABLE);

  Serial.println("BT device name set to: VEYA-OBD-SAMPLE");
  Serial.println("Waiting for RFCOMM connection...");

  lastTelemetryMs = millis();
}

void loop() {
  // Check if client has connected
  if (SerialBT.hasClient()) {
    if (!clientConnected) {
      clientConnected = true;
      helloSent = false;
      Serial.println("Client connected!");
    }

    // Send hello frame on first connection
    if (!helloSent) {
      String hello = "{\"schema\":1,\"type\":\"hello\",\"source_id\":\"esp32-sample\",";
      hello += "\"source_kind\":\"veya-esp32\",\"firmware\":\"sample-1.0\"}";
      SerialBT.println(hello);
      Serial.print("Hello sent: ");
      Serial.println(hello);
      helloSent = true;
      lastTelemetryMs = millis();
    }

    // Send telemetry frame every 100ms
    if (millis() - lastTelemetryMs >= TELEMETRY_INTERVAL_MS) {
      lastTelemetryMs = millis();

      // Build telemetry frame with hardcoded values
      // Replace these values with real OBD readings in production
      char telemetry[256];
      snprintf(telemetry, sizeof(telemetry),
        "{\"schema\":1,\"type\":\"telemetry\",\"ts\":%lu,"
        "\"rpm\":850,\"speed_kph\":0,\"coolant_c\":85,\"throttle_pct\":12,"
        "\"engine_load\":15,\"battery_v\":14.2,\"fuel_level\":50,\"intake_temp_c\":30}",
        millis());

      SerialBT.println(telemetry);
    }
  } else {
    // Client disconnected
    if (clientConnected) {
      clientConnected = false;
      helloSent = false;
      Serial.println("Client disconnected. Waiting for reconnection...");
    }
    delay(100);
  }
}

/*
 * To read real OBD data instead of hardcoded values:
 *
 * 1. In setup(), initialize your OBD communication (e.g., CAN bus, UART to OBD module)
 * 2. In loop(), inside the telemetry frame section, replace the hardcoded values with
 *    actual OBD reads (e.g., rpm = readRPM(), speed_kph = readSpeed(), etc.)
 *
 * Example:
 *   int rpm = readRPMFromOBD();
 *   float speed = readSpeedFromOBD();
 *   snprintf(telemetry, sizeof(telemetry),
 *     "{\"schema\":1,\"type\":\"telemetry\",\"ts\":%lu,"
 *     "\"rpm\":%d,\"speed_kph\":%.1f,...}", millis(), rpm, speed);
 */
