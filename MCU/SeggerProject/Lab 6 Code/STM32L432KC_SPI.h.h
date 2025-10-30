/**
 * @file spi.h
 * @brief Minimal SPI1 driver for STM32L432 (CMSIS-only; no HAL).
 *
 * Big picture:
 *  - We use SPI1 in MASTER mode to talk to the DS1722 temperature sensor.
 *  - SPI pins: SCK=PA5, MISO=PA6, MOSI=PA7 (Alternate Function AF5).
 *  - DS1722 CE (chip-enable) is *ACTIVE-HIGH* and driven by PB4 (GPIO).
 *  - We manage CE manually in software (not using hardware NSS).
 *
 * Public API (simple on purpose):
 *    void    spi1_init(void);
 *    uint8_t spi1_txrx(uint8_t tx);
 *    ds1722_ce_high(), ds1722_ce_low() helpers to bracket transactions.
 */

#ifndef SPI_H
#define SPI_H

#include "stm32l432xx.h"
#include <stdint.h>

// ---------------------- SPI1 pin map (AF5 on GPIOA) ----------------------
#define SPI1_SCK_PORT   GPIOA
#define SPI1_SCK_PIN    5u
#define SPI1_MISO_PORT  GPIOA
#define SPI1_MISO_PIN   6u
#define SPI1_MOSI_PORT  GPIOA
#define SPI1_MOSI_PIN   7u

// ---------------------- DS1722 CE pin (ACTIVE-HIGH) ----------------------
#define DS1722_CE_PORT  GPIOB
#define DS1722_CE_PIN   4u

// Initialize GPIO + SPI1 (master, 8-bit frames, MSB-first, CPOL=0, CPHA=1)
void spi1_init(void);

// Full-duplex 8-bit transfer, blocking.
uint8_t spi1_txrx(uint8_t tx);

// CE helpers (ACTIVE-HIGH): call high() to start, low() to end
static inline void ds1722_ce_high(void) { DS1722_CE_PORT->BSRR = (1u << DS1722_CE_PIN); }
static inline void ds1722_ce_low(void)  { DS1722_CE_PORT->BRR  = (1u << DS1722_CE_PIN); }

#endif // SPI_H
