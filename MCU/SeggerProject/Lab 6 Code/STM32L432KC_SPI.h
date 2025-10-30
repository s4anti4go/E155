// STM32L432KC_SPI.h
// santiago
// Purpose: Minimal SPI1 master driver using CMSIS (no HAL).
// NOTE: Pin map below uses PA5/PA6/PA7 for SPI1 and PB4 for CE.
//       CE is ACTIVE-HIGH for DS1722.

#ifndef STM32L4_SPI_H
#define STM32L4_SPI_H

#include <stdint.h>
#include "stm32l432xx.h"
#include "STM32L432KC_GPIO.h"  // for pinMode(), gpioPinToBase(), gpioPinOffset()

//SPI pin 


 
#define SPI_SCK   PA5     
#define SPI_MISO  PB4    
#define SPI_MOSI  PA12     
#define SPI_CE    PA6     

// Initializes SPI1 as master.
//  br   = 0..7  (SCK = PCLK / 2^(br+1); keep <= 5 MHz for DS1722)
//  cpol = 0 or 1
//  cpha = 0 or 1  (DS1722 REQUIRES cpha=1; pass 1)
void initSPI(int br, int cpol, int cpha);

// Blocking full-duplex transfer of one byte
uint8_t spiSendReceive(uint8_t send);

// Manual CE control (ACTIVE-HIGH)
static inline void spi_ce_high(void) { digitalWrite(SPI_CE, PIO_HIGH); }
static inline void spi_ce_low(void)  { digitalWrite(SPI_CE, PIO_LOW);  }

#endif // STM32L4_SPI_H