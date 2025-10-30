// DS1722.c
// DS1722 helpers using STM32L432KC_SPI driver. CE is ACTIVE-HIGH.

#include "DS1722.h"
#include "STM32L432KC_SPI.h"

// Register addresses (SPI mode)
#define DS1722_ADDR_CONFIG_R   0x00u
#define DS1722_ADDR_TEMP_LSB   0x01u
#define DS1722_ADDR_TEMP_MSB   0x02u
#define DS1722_ADDR_CONFIG_W   0x80u

// CONFIG bits (format: 1 1 1  1SHOT  R2 R1 R0  SD)
#define DS1722_SD_BIT      (1u<<0)
#define DS1722_R0_BIT      (1u<<1)
#define DS1722_R1_BIT      (1u<<2)
#define DS1722_R2_BIT      (1u<<3)
#define DS1722_1SHOT_BIT   (1u<<4)

// ---------- single-CE-window helpers ----------
static inline void txn_begin(void){ spi_ce_high(); }
static inline void txn_end(void)  { spi_ce_low();  }

static void ds1722_read_burst(uint8_t start_addr, uint8_t *buf, int n){
    txn_begin();
    (void)spiSendReceive(start_addr);         // send start address
    for (int i=0; i<n; i++) buf[i] = spiSendReceive(0x00);
    txn_end();
}

static void ds1722_write1(uint8_t addr_w, uint8_t data){
    txn_begin();
    (void)spiSendReceive(addr_w);             // write-address (0x80)
    (void)spiSendReceive(data);               // data
    txn_end();
}

// ---------- public API ----------
uint8_t readConfiguration(void){
    uint8_t b=0;
    ds1722_read_burst(DS1722_ADDR_CONFIG_R, &b, 1);
    return b;
}

void setTempConfiguration(int bits){
    // Map bits to R2..R0 (8..12-bit)
    uint8_t r = 0;
    switch(bits){
        case 8:  r = 0; break;                                  // 000
        case 9:  r = DS1722_R0_BIT; break;                      // 001
        case 10: r = DS1722_R1_BIT; break;                      // 010
        case 11: r = DS1722_R1_BIT | DS1722_R0_BIT; break;      // 011
        case 12: r = DS1722_R2_BIT; break;                      // 1xx
        default: r = DS1722_R2_BIT; break;                      // default 12-bit
    }

    // Build an exact CONFIG byte:
    //   top nibble must be 1110 (1SHOT=0), SD=0 (continuous), R2:R1:R0 per 'r'
    //   E0 | r gives: 8-bit=E0, 9-bit=E2, 10-bit=E4, 11-bit=E6, 12-bit=E8
    uint8_t cfg = 0xE0u | r;
    ds1722_write1(DS1722_ADDR_CONFIG_W, cfg);

    // Optional: wait or discard one sample (12-bit worst ~1.2 s) before trusting next read.
}

uint8_t readTempLSB(void){
    uint8_t b=0;
    ds1722_read_burst(DS1722_ADDR_TEMP_LSB, &b, 1);
    return b;
}
uint8_t readTempMSB(void){
    uint8_t b=0;
    ds1722_read_burst(DS1722_ADDR_TEMP_MSB, &b, 1);
    return b;
}

float ds1722_read_celsius(void){
    // Read LSB then MSB under one CE window; Q8.8 signed fixed point
    uint8_t buf[2];
    ds1722_read_burst(DS1722_ADDR_TEMP_LSB, buf, 2);
    int16_t raw = (int16_t)((((uint16_t)buf[1])<<8) | buf[0]);
    return (float)raw / 256;
}
