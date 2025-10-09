/*********************************************************************
*  main.c — E155 Lab 4: Edge-to-Start 
*  - Audio out:   PA11  (toggle to LM386 IN+ via pot/divider)
*  - FÜR ELISE:   PB4   (read LOW -> start & play to completion)
*  - IMPERIAL:    PA6   (read LOW -> start & play to completion)
*  - Santiago Burgos-Fallon
*  - Updated 10/02/2025
*********************************************************************/

#define PERIPH_BASE       0x40000000UL
#define AHB1PERIPH_BASE   0x40020000UL
#define AHB2PERIPH_BASE   0x48000000UL
#define RCC_BASE          (AHB1PERIPH_BASE + 0x1000UL)   // 0x40021000
#define TIM2_BASE         (PERIPH_BASE + 0x0000UL)       // 0x40000000
#define GPIOA_BASE        (AHB2PERIPH_BASE + 0x0000UL)   // 0x48000000
#define GPIOB_BASE        (AHB2PERIPH_BASE + 0x0400UL)   // 0x48000400

/* RCC enables */
#define RCC_AHB2ENR   (*(volatile unsigned int*)(RCC_BASE + 0x4C))
#define RCC_APB1ENR1  (*(volatile unsigned int*)(RCC_BASE + 0x58))
#define GPIOAEN       (1u<<0)
#define GPIOBEN       (1u<<1)
#define TIM2EN        (1u<<0)

/* GPIOA */
#define GPIOA_MODER   (*(volatile unsigned int*)(GPIOA_BASE + 0x00))
#define GPIOA_PUPDR   (*(volatile unsigned int*)(GPIOA_BASE + 0x0C))
#define GPIOA_IDR     (*(volatile unsigned int*)(GPIOA_BASE + 0x10))
#define GPIOA_ODR     (*(volatile unsigned int*)(GPIOA_BASE + 0x14))
#define GPIOA_BSRR    (*(volatile unsigned int*)(GPIOA_BASE + 0x18))

/* GPIOB  */
#define GPIOB_MODER   (*(volatile unsigned int*)(GPIOB_BASE + 0x00))
#define GPIOB_PUPDR   (*(volatile unsigned int*)(GPIOB_BASE + 0x0C))
#define GPIOB_IDR     (*(volatile unsigned int*)(GPIOB_BASE + 0x10))

/* TIM2 */
#define TIM2_CR1      (*(volatile unsigned int*)(TIM2_BASE + 0x00))
#define TIM2_SR       (*(volatile unsigned int*)(TIM2_BASE + 0x10))
#define TIM2_EGR      (*(volatile unsigned int*)(TIM2_BASE + 0x14))
#define TIM2_CNT      (*(volatile unsigned int*)(TIM2_BASE + 0x24))
#define TIM2_PSC      (*(volatile unsigned int*)(TIM2_BASE + 0x28))
#define TIM2_ARR      (*(volatile unsigned int*)(TIM2_BASE + 0x2C))
#define TIM_CR1_CEN   (1u<<0)
#define TIM_EGR_UG    (1u<<0)
#define TIM_SR_UIF    (1u<<0)

/* Pins */
#define AUDIO_PIN        11u  /* PA11: toggle to LM386 IN+ */
#define START_FUR_PIN_B   4u  /* PB4  -> start Für Elise when LOW */
#define START_IMP_PIN_A   6u  /* PA6  -> start Imperial when LOW */

/*Timer input clock (Hz) */
#ifndef TIMER_CLK_HZ
#define TIMER_CLK_HZ 4000000UL
#endif

/* Für Elise (Hz, ms) */
static const int fur_elise[][2] = {
  {659,125},{623,125},{659,125},{623,125},{659,125},{494,125},{587,125},{523,125},{440,250},{0,125},
  {262,125},{330,125},{440,125},{494,250},{0,125},{330,125},{416,125},{494,125},{523,250},{0,125},
  {330,125},{659,125},{623,125},{659,125},{623,125},{659,125},{494,125},{587,125},{523,125},{440,250},
  {0,125},{262,125},{330,125},{440,125},{494,250},{0,125},{330,125},{523,125},{494,125},{440,250},
  {0,125},{494,125},{523,125},{587,125},{659,375},{392,125},{699,125},{659,125},{587,375},{349,125},
  {659,125},{587,125},{523,375},{330,125},{587,125},{523,125},{494,250},{0,125},{330,125},{659,125},
  {0,250},{659,125},{1319,125},{0,250},{623,125},{659,125},{0,250},{623,125},{659,125},{623,125},
  {659,125},{623,125},{659,125},{494,125},{587,125},{523,125},{440,250},{0,125},{262,125},{330,125},
  {440,125},{494,250},{0,125},{330,125},{416,125},{494,125},{523,250},{0,125},{330,125},{659,125},
  {623,125},{659,125},{623,125},{659,125},{494,125},{587,125},{523,125},{440,250},{0,125},{262,125},
  {330,125},{440,125},{494,250},{0,125},{330,125},{523,125},{494,125},{440,500},{0,0}
};

/*Imperial March (Hz, ms) — tempo 120 BPM */
static const int imperial[][2] = {
  {440,750},{440,750},{440,125},{440,125},{440,125},{440,125},{349,250},{0,250},
  {440,750},{440,750},{440,125},{440,125},{440,125},{440,125},{349,250},{0,250},
  {440,500},{440,500},{440,500},{349,375},{523,125},
  {440,500},{349,375},{523,125},{440,1000},
  {659,500},{659,500},{659,500},{698,375},{523,125},
  {440,500},{349,375},{523,125},{440,1000},
  {880,500},{440,375},{440,125},{880,500},{831,375},{784,125},
  {622,125},{587,125},{622,250},{0,250},{440,250},{622,500},{587,375},{554,125},
  {523,125},{494,125},{523,125},{0,250},{349,250},{415,500},{349,375},{440,188},
  {523,500},{440,375},{523,125},{659,1000},
  {880,500},{440,375},{440,125},{880,500},{831,375},{784,125},
  {622,125},{587,125},{622,250},{0,250},{440,250},{622,500},{587,375},{554,125},
  {523,125},{494,125},{523,125},{0,250},{349,250},{415,500},{349,375},{440,188},
  {440,500},{349,375},{523,125},{440,1000},
  {0,0}
};

/* Helpers */
static void audio_init_pa_output(void) {
  RCC_AHB2ENR |= GPIOAEN;
  GPIOA_MODER &= ~(3u << (AUDIO_PIN*2));
  GPIOA_MODER |=  (1u << (AUDIO_PIN*2));   /* PA11 = output */
  GPIOA_BSRR = (1u << (AUDIO_PIN + 16));   /* drive low */
}

static void buttons_init(void) {
  RCC_AHB2ENR |= GPIOAEN | GPIOBEN;

  /* PB4 input + pull-up (start Für Elise) */
  GPIOB_MODER &= ~(3u << (START_FUR_PIN_B*2));
  GPIOB_PUPDR &= ~(3u << (START_FUR_PIN_B*2));
  GPIOB_PUPDR |=  (1u << (START_FUR_PIN_B*2));

  /* PA6 input + pull-up (start Imperial) */
  GPIOA_MODER &= ~(3u << (START_IMP_PIN_A*2));
  GPIOA_PUPDR &= ~(3u << (START_IMP_PIN_A*2));
  GPIOA_PUPDR |=  (1u << (START_IMP_PIN_A*2));
}

static inline int fur_low(void) { return ((GPIOB_IDR >> START_FUR_PIN_B) & 1u) == 0; }
static inline int imp_low(void) { return ((GPIOA_IDR >> START_IMP_PIN_A) & 1u) == 0; }

static void tim2_init_1MHz_tick(void) {
  RCC_APB1ENR1 |= TIM2EN;
  TIM2_CR1 &= ~TIM_CR1_CEN;
  unsigned psc = (TIMER_CLK_HZ / 1000000UL);
  if (psc) --psc;
  TIM2_PSC = psc;                 /* 1 µs per tick */
  TIM2_ARR = 999;                 /* placeholder (1 ms) */
  TIM2_EGR = TIM_EGR_UG;          /* latch PSC/ARR */
  TIM2_CNT = 0;
  TIM2_SR  = 0;
  TIM2_CR1 |= TIM_CR1_CEN;
}

static inline void tim2_wait_update(void) {
  while ((TIM2_SR & TIM_SR_UIF) == 0) { /* spin */ }
  TIM2_SR = 0; /* clear UIF */
}

static inline void audio_toggle(void) { GPIOA_ODR ^= (1u << AUDIO_PIN); }
static inline void audio_low(void)    { GPIOA_BSRR = (1u << (AUDIO_PIN + 16)); }

static void play_rest_ms(int ms) {
  TIM2_CR1 &= ~TIM_CR1_CEN;
  TIM2_ARR = 999;    /* 1 ms per update @ 1 MHz tick */
  TIM2_EGR = TIM_EGR_UG;
  TIM2_CNT = 0;
  TIM2_SR  = 0;
  TIM2_CR1 |= TIM_CR1_CEN;
  for (int i = 0; i < ms; ++i) tim2_wait_update();
}

static void play_note(int freq_hz, int duration_ms) {
  if (duration_ms <= 0) return;
  if (freq_hz <= 0) { play_rest_ms(duration_ms); return; }

  /* half-period (µs); ARR = half_us - 1 */
  unsigned long half_us = (500000UL + (unsigned long)freq_hz/2) / (unsigned long)freq_hz;
  if (half_us == 0) half_us = 1;
  unsigned long arr = half_us - 1;

  TIM2_CR1 &= ~TIM_CR1_CEN;
  TIM2_ARR  = (unsigned)arr;
  TIM2_EGR  = TIM_EGR_UG;
  TIM2_CNT  = 0;
  TIM2_SR   = 0;
  TIM2_CR1 |= TIM_CR1_CEN;

  /* toggles ≈ round(2*f*ms/1000) */
  unsigned long long toggles =
      ((unsigned long long)freq_hz * (unsigned long long)duration_ms * 2ULL + 500ULL) / 1000ULL;

  for (unsigned long long i = 0; i < toggles; ++i) {
    tim2_wait_update();
    audio_toggle();
  }
  audio_low();
}

static void play_score(const int score[][2]) {
  for (int i = 0; ; ++i) {
    int f = score[i][0], d = score[i][1];
    if (d == 0) break;
    play_note(f, d);
  }
}

/* main */
int main(void) {
  audio_init_pa_output();
  buttons_init();
  tim2_init_1MHz_tick();
  audio_low();

  for (;;) {
    if (fur_low()) {
      play_score(fur_elise);   
    } else if (imp_low()) {
      play_score(imperial);    
    }
  }
}
