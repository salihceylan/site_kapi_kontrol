#pragma once

#include <Arduino.h>
#include <Wire.h>

// CST816D / CST816T Capacitive Touch Controller I2C Driver
// Standard I2C Address: 0x15
#define CST816D_I2C_ADDR 0x15

class CST816DTouch {
public:
  CST816DTouch() : _sdaPin(-1), _sclPin(-1), _rstPin(-1), _intPin(-1), _initialized(false) {}

  // Birden fazla kez cagrilabilir (main.cpp: acilista bir kez, hazir degilse 5 sn'de bir yeniden dener; ~60 ms bloklar).
  // verbose=false: yeniden denemelerde "algilanamadi" satiri seri portu doldurmasin (basari her zaman yazilir).
  bool begin(int sda, int scl, int rst = -1, int irq = -1, bool verbose = true) {
    _sdaPin = sda;
    _sclPin = scl;
    _rstPin = rst;
    _intPin = irq;

    // Reset sequence if reset pin is configured
    if (_rstPin >= 0) {
      pinMode(_rstPin, OUTPUT);
      digitalWrite(_rstPin, LOW);
      delay(10);
      digitalWrite(_rstPin, HIGH);
      delay(50);
    }

    if (_intPin >= 0) {
      pinMode(_intPin, INPUT_PULLUP);
    }

    // Yeniden denemede I2C gercekten sifirlansin: arduino-esp32 2.0.14'te Wire.begin() zaten baslatilmissa hicbir sey yapmaz.
    // Wire.end() baslatilmamis veriyolunda zararsizdir; sira: end() -> begin().
    Wire.end();
    Wire.begin(_sdaPin, _sclPin, 400000);

    // Test communication with CST816D
    Wire.beginTransmission(CST816D_I2C_ADDR);
    if (Wire.endTransmission() == 0) {
      _initialized = true;
      Serial.println("[TOUCH] CST816D touch controller initialized at 0x15");
      return true;
    }

    if (verbose) {
      Serial.println("[TOUCH] CST816D not detected (fallback to button input)");
    }
    _initialized = false;
    return false;
  }

  bool isAvailable() const {
    return _initialized;
  }

  // Non-blocking read of touch coordinates
  bool readTouch(int16_t &x, int16_t &y) {
    if (!_initialized) return false;

    Wire.beginTransmission(CST816D_I2C_ADDR);
    Wire.write(0x02); // Register 0x02: Finger Num
    if (Wire.endTransmission(false) != 0) return false;

    if (Wire.requestFrom((uint8_t)CST816D_I2C_ADDR, (size_t)5) != 5) return false;

    uint8_t fingerNum = Wire.read();
    uint8_t xHigh = Wire.read();
    uint8_t xLow = Wire.read();
    uint8_t yHigh = Wire.read();
    uint8_t yLow = Wire.read();

    if (fingerNum == 0) return false;

    x = ((xHigh & 0x0F) << 8) | xLow;
    y = ((yHigh & 0x0F) << 8) | yLow;

    // Constrain to display bounds (240x320)
    x = constrain(x, 0, 240);
    y = constrain(y, 0, 320);

    return true;
  }

private:
  int _sdaPin;
  int _sclPin;
  int _rstPin;
  int _intPin;
  bool _initialized;
};
