// STM32L432KC_SPI.c
//santiago
// CMSIS-only SPI1 master driver tuned for DS1722 (CPHA=1, 8-bit, software NSS).

#include "STM32L432KC_SPI.h"
#include "STM32L432KC_RCC.h"

// Helpers to decode PAx index quickly
#define PIN_IDX(pin)      (gpioPinOffset(pin))
#define IS_PA(pin)        (gpioPinToBase(pin) == GPIOA)
#define IS_PB(pin)        (gpioPinToBase(pin) == GPIOB)

static void set_af5(GPIO_TypeDef* port, uint8_t pin_idx) {
    if (pin_idx < 8) {
        // AFRL
        port->AFR[0] &= ~(0xFu << (pin_idx * 4));
        port->AFR[0] |=  (0x5u << (pin_idx * 4));  // AF5
    } else {
        // AFRH
        uint8_t i = pin_idx - 8;
        port->AFR[1] &= ~(0xFu << (i * 4));
        port->AFR[1] |=  (0x5u << (i * 4));        // AF5
    }
}

static void gpio_spi_init(void) {
    // Enable GPIOA / GPIOB clocks (for our chosen pins)
    RCC->AHB2ENR |= RCC_AHB2ENR_GPIOAEN | RCC_AHB2ENR_GPIOBEN;

    // CE output, default LOW (inactive for ACTIVE-HIGH)
    pinMode(SPI_CE, GPIO_OUTPUT);
    spi_ce_low();

    // SCK/MISO/MOSI as alternate function
    pinMode(SPI_SCK,  GPIO_ALT);
    pinMode(SPI_MISO, GPIO_ALT);
    pinMode(SPI_MOSI, GPIO_ALT);

    // Select AF5 on these pins
    set_af5(gpioPinToBase(SPI_SCK),  PIN_IDX(SPI_SCK));
    set_af5(gpioPinToBase(SPI_MISO), PIN_IDX(SPI_MISO));
    set_af5(gpioPinToBase(SPI_MOSI), PIN_IDX(SPI_MOSI));

    // High speed

    // 1. Configure Port A pins (SCK = PA6)
    GPIO_TypeDef *pa = GPIOA;
    // High speed for PA6
    pa->OSPEEDR |= (3u << (2*PIN_IDX(SPI_SCK)));
    // Push-pull for PA6
    pa->OTYPER &= ~(1u << PIN_IDX(SPI_SCK));
    // No pulls for PA6
    pa->PUPDR  &= ~(3u << (2*PIN_IDX(SPI_SCK)));

    // 2. Configure Port B pins (MISO = PB4, MOSI = PB1)
    GPIO_TypeDef *pb = GPIOB;
    // High speed for PB4 and PB1
    pb->OSPEEDR |= (3u << (2*PIN_IDX(SPI_MISO)))
                 | (3u << (2*PIN_IDX(SPI_MOSI)));
    // Push-pull for PB4 and PB1
    pb->OTYPER &= ~((1u << PIN_IDX(SPI_MISO))
                  | (1u << PIN_IDX(SPI_MOSI)));
    // No pulls for PB4 and PB1
    pb->PUPDR  &= ~((3u << (2*PIN_IDX(SPI_MISO)))
                  | (3u << (2*PIN_IDX(SPI_MOSI))));
}

void initSPI(int br, int cpol, int cpha) {
    gpio_spi_init();

    // Enable SPI1 clock
    RCC->APB2ENR |= RCC_APB2ENR_SPI1EN;

    // Disable SPI before config
    SPI1->CR1 &= ~SPI_CR1_SPE;

    // Clean slate
    SPI1->CR1 = 0;
    SPI1->CR2 = 0;

    // Baud rate prescaler
    SPI1->CR1 &= ~SPI_CR1_BR;
    SPI1->CR1 |= ((br & 0x7) << SPI_CR1_BR_Pos);

    // CPOL/CPHA (DS1722 requires CPHA=1)
    if (cpol) SPI1->CR1 |= SPI_CR1_CPOL;
    if (cpha) SPI1->CR1 |= SPI_CR1_CPHA;

    // Master, MSB-first
    SPI1->CR1 |= SPI_CR1_MSTR;

    // Software slave management (we drive CE via GPIO)
    SPI1->CR1 |= SPI_CR1_SSM | SPI_CR1_SSI;

    // 8-bit frames + FRXTH (RXNE set per 8-bit)
    SPI1->CR2 |= (7u << SPI_CR2_DS_Pos) | SPI_CR2_FRXTH;
    // NSS output disabled
    SPI1->CR2 &= ~SPI_CR2_SSOE;

    // Enable SPI
    SPI1->CR1 |= SPI_CR1_SPE;
}

uint8_t spiSendReceive(uint8_t send) {
    // Wait until TX buffer empty
    while(!(SPI1->SR & SPI_SR_TXE)) {}
    // 8-bit write
    *(volatile uint8_t *)&SPI1->DR = send;
    // Wait for RX
    while(!(SPI1->SR & SPI_SR_RXNE)) {}
    // 8-bit read
    return *(volatile uint8_t *)&SPI1->DR;
}
