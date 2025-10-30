// DS1722.h
// Author: (your name)
// Purpose: DS1722 helper functions matching the course API, built on our SPI driver.

#ifndef DS1722_H
#define DS1722_H

#include <stdint.h>

// Read CONFIG register (addr 0x00)
uint8_t readConfiguration(void);

// Set resolution bits based on "bits" (8/9/10/11/12). Leaves SD=0 (continuous).
void setTempConfiguration(int bits) ;

// Read raw temperature bytes (LSB at 0x01, MSB at 0x02)
uint8_t readTempLSB(void);
uint8_t readTempMSB(void);

// (Optional helper) Combine MSB/LSB to °C
float ds1722_read_celsius(void);

#endif
