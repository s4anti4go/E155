// main.c — Lab 5: Quadrature via EXTI (STM32L432KC)
// A=PA6 (EXTI6), B=PB4 (EXTI4). ITM/SWO printf at ≥1 Hz.

#include "stm32l432xx.h"
#include <stdio.h>
#include <stdint.h>

// --- printf over ITM/SWO (matches class example) ---
int _write(int file, char *ptr, int len) {
  (void)file;
  for (int i = 0; i < len; i++) ITM_SendChar((uint32_t)(uint8_t)(*ptr++));
  return len;
}

// --- Encoder pins & constants ---
#define ENC_A_PORT GPIOA
#define ENC_A_PIN  6u      // PA6 -> EXTI6
#define ENC_B_PORT GPIOB
#define ENC_B_PIN  4u      // PB4 -> EXTI4
#define ENC_PPR_X1 120
#define ENC_CPR_X4 (4 * ENC_PPR_X1)

// --- Globals shared with ISRs ---
volatile uint32_t ms = 0;            // SysTick ms
volatile uint8_t  oldState = 0;      // packed A<<1|B (0..3)
volatile int32_t  tick_count = 0;    // signed ticks (+/-)
volatile uint32_t last_edge_ms = 0;  // time of last valid edge

// Pack A,B (read actual pins) -> 0..3
static inline uint8_t read_AB(void) {
  uint8_t a = (ENC_A_PORT->IDR >> ENC_A_PIN) & 1u;
  uint8_t b = (ENC_B_PORT->IDR >> ENC_B_PIN) & 1u;
  return (uint8_t)((a << 1) | b);
}

// 16-entry transition table: idx=(old<<2)|curr; +1 fwd, -1 rev, 0 invalid
static const int8_t QEM16[16] = {
  /*old=00*/  0, +1, -1,  0,
  /*old=01*/ -1,  0,  0, +1,
  /*old=10*/ +1,  0,  0, -1,
  /*old=11*/  0, -1, +1,  0
};

static inline void update_from_pins(void) {
  uint8_t curr  = read_AB();
  uint8_t index = (uint8_t)((oldState << 2) | curr);
  int8_t  d     = QEM16[index];
  if (d != 0) { tick_count += d; last_edge_ms = ms; }
  oldState = curr;
}

// --- ISRs ---
void SysTick_Handler(void) { ms++; }

void EXTI4_IRQHandler(void) {            // PB4 (line 4)
  if (EXTI->PR1 & (1u << 4)) {
    EXTI->PR1 = (1u << 4);               // clear
    update_from_pins();                  // ±1 tick or 0
  }
}

void EXTI9_5_IRQHandler(void) {          // PA6 (line 6)
  if (EXTI->PR1 & (1u << 6)) {
    EXTI->PR1 = (1u << 6);
    update_from_pins();
  }
}

// --- Init ---
static void gpio_init_AB(void) {
  RCC->AHB2ENR |= RCC_AHB2ENR_GPIOAEN | RCC_AHB2ENR_GPIOBEN;
  ENC_A_PORT->MODER &= ~(0x3u << (ENC_A_PIN * 2)); // input
  ENC_B_PORT->MODER &= ~(0x3u << (ENC_B_PIN * 2)); // input
  ENC_A_PORT->PUPDR = (ENC_A_PORT->PUPDR & ~(0x3u << (ENC_A_PIN * 2))) | (0x1u << (ENC_A_PIN * 2)); // PU
  ENC_B_PORT->PUPDR = (ENC_B_PORT->PUPDR & ~(0x3u << (ENC_B_PIN * 2))) | (0x1u << (ENC_B_PIN * 2)); // PU
}

static void exti_init_AB(void) {
  RCC->APB2ENR |= RCC_APB2ENR_SYSCFGEN;          // route EXTI
  // EXTICR[1]: lines 4..7 nibble-mapped; EXTI4←PB (1), EXTI6←PA (0)
  SYSCFG->EXTICR[1] &= ~((0xFu << 0) | (0xFu << 8));
  SYSCFG->EXTICR[1] |=  ((0x1u << 0) | (0x0u << 8));
  EXTI->IMR1  |= (1u << 4) | (1u << 6);          // unmask
  EXTI->RTSR1 |= (1u << 4) | (1u << 6);          // rising
  EXTI->FTSR1 |= (1u << 4) | (1u << 6);          // falling
  EXTI->PR1    = (1u << 4) | (1u << 6);          // clear pending
  NVIC_EnableIRQ(EXTI4_IRQn);
  NVIC_EnableIRQ(EXTI9_5_IRQn);
}

static void systick_init_1kHz(void) {
  SystemCoreClockUpdate();
  SysTick_Config(SystemCoreClock / 1000u);
}

// --- Main ---
int main(void) {
  gpio_init_AB();
  exti_init_AB();
  systick_init_1kHz();

  oldState = read_AB();                 // seed
  last_edge_ms = ms;

  uint32_t t_prev   = ms;
  int32_t  ticks_prev = 0;

  printf("Lab5 Quadrature: A=PA6, B=PB4, CPRx4=%d\n", ENC_CPR_X4);

  for (;;) {
    if ((ms - t_prev) >= 1000u) {      // 1 Hz update
      int32_t ticks_now = tick_count;
      int32_t dticks    = ticks_now - ticks_prev;
      float   dt_s      = (ms - t_prev) / 1000.0f;

      float rps = ((float)dticks / (float)ENC_CPR_X4) / dt_s;
      if ((ms - last_edge_ms) > 500u) rps = 0.0f; // zero when still

      const char* dir = (dticks > 0) ? "FWD" : (dticks < 0) ? "REV" : "STILL";
      printf("vel=%0.5f rev/s  dir=%s  (dticks=%ld)\n",
             (double)rps, dir, (long)dticks);

      t_prev     = ms;
      ticks_prev = ticks_now;
    }
  }
}
