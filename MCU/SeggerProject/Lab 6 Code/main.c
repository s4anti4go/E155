/*
 * main.c
 * Uses: STM32L432KC_* helpers + STM32L432KC_SPI + DS1722
 * UART1 @ 125000 to ESP8266; SPI1 to DS1722; LED on PB3
 */

#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include "main.h"

// helper headers
#include "STM32L432KC_GPIO.h"
#include "STM32L432KC_RCC.h"
#include "STM32L432KC_FLASH.h"
#include "STM32L432KC_USART.h"
#include "STM32L432KC_TIM.h"

// SPI + DS1722 adapters
#include "STM32L432KC_SPI.h"
#include "DS1722.h"

// Simple HTML 
static char* webpageStart =
"<!DOCTYPE html><html><head><title>E155 Web Server Demo Webpage</title>"
"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
"<style>body{font-family:system-ui;margin:1.2rem;}button,input{font-size:1.1rem;}"
".note{color:#666;font-size:.9rem}</style>"
"</head><body><h1>E155 Web Server Demo Webpage</h1>";

static char* ledStr =
"<h2>LED Control</h2>"
"<form action=\"ledon\"><input type=\"submit\" value=\"Turn the LED on!\"></form>"
"<form action=\"ledoff\"><input type=\"submit\" value=\"Turn the LED off!\"></form>";

static char* webpageEnd = "</body></html>";

// Helpers 
static int inString(char request[], const char des[]) {
  return (strstr(request, des) != NULL) ? 1 : -1;
}

static int updateLEDStatus(char request[]) {
  int led_status = 0;
  if (inString(request, "ledoff")==1) { digitalWrite(LED_PIN, 0); led_status = 0; }
  else if (inString(request, "ledon")==1) { digitalWrite(LED_PIN, 1); led_status = 1; }
  return led_status;
}

static void maybe_update_resolution(char request[]) {
  if (inString(request, "res8")==1 || inString(request, "8bit")==1)       { setTempConfiguration(8);  }
  else if (inString(request, "res9")==1 || inString(request, "9bit")==1)  { setTempConfiguration(9);  }
  else if (inString(request, "res10")==1|| inString(request, "10bit")==1) { setTempConfiguration(10); }
  else if (inString(request, "res11")==1|| inString(request, "11bit")==1) { setTempConfiguration(11); }
  else if (inString(request, "res12")==1|| inString(request, "12bit")==1) { setTempConfiguration(12); }
}

static void resolutionControls(USART_TypeDef *USART) {
  sendString(USART, "<h2>Temperature</h2>");
  sendString(USART, "<p>Select DS1722 resolution:</p><div style='display:flex;gap:.5rem;flex-wrap:wrap'>");
  sendString(USART, "<form action=\"res8\"><input type=\"submit\" value=\"8-bit\"></form>");
  sendString(USART, "<form action=\"res9\"><input type=\"submit\" value=\"9-bit\"></form>");
  sendString(USART, "<form action=\"res10\"><input type=\"submit\" value=\"10-bit\"></form>");
  sendString(USART, "<form action=\"res11\"><input type=\"submit\" value=\"11-bit\"></form>");
  sendString(USART, "<form action=\"res12\"><input type=\"submit\" value=\"12-bit\"></form>");
  sendString(USART, "</div>");
}

// Extract 8/9/10/11/12-bit from CONFIG (R2:R1:R0 at bits 3..1; 1xx→12)
static int ds1722_bits_from_cfg(uint8_t cfg){
  uint8_t r = (cfg >> 1) & 0x7;
  switch (r) {
    case 0: return 8;
    case 1: return 9;
    case 2: return 10;
    case 3: return 11;
    default: return 12;
  }
}

// Number of decimals to print for a given resolution
static int decimals_for_bits(int bits){
  if (bits <= 8) return 0;
  int d = bits - 8;        // 9→1, 10→2, 11→3, 12→4
  return (d > 4) ? 4 : d;
}

// Quantize a °C value to the sensor’s LSB step for the current resolution
static float quantize_by_bits(float tC, int bits){
  int shift = (bits <= 8) ? 0 : (bits - 8);
  float step = 1.0f / (float)(1u << shift);   // 8→1.0, 9→0.5, 10→0.25, 11→0.125, 12→0.0625
  // symmetric round to nearest step without <math.h>
  float scaled = tC / step;
  int32_t q = (int32_t)((scaled >= 0.0f) ? (scaled + 0.5f) : (scaled - 0.5f));
  return q * step;
}

// Pretty-print temperature with the right decimals + a note showing resolution and step
static void print_temperature_block(USART_TypeDef *USART){
  // Read config first so we know resolution, then temperature
  uint8_t cfg = readConfiguration();
  int bits = ds1722_bits_from_cfg(cfg);
  int dec  = decimals_for_bits(bits);

  float tC_raw = ds1722_read_celsius();
  float tC = quantize_by_bits(tC_raw, bits);      // optional, makes display match actual step
  float tF = (tC * 9.0f / 5.0f) + 32.0f;

  // dynamic format string with appropriate decimals
  char fmt[64], buf[128];
  snprintf(fmt, sizeof(fmt),
           "<p><b>Current temperature:</b> %%.%df &deg;C (%%.%df &deg;F)</p>",
           dec, dec);
  snprintf(buf, sizeof(buf), fmt, tC, tF);
  sendString(USART, buf);

  // Show resolution + step and the raw CONFIG (handy for debugging)
  float step = 1.0f / (float)(1u << ((bits <= 8)? 0 : (bits - 8)));
  snprintf(buf, sizeof(buf),
           "<p class='note'>Resolution: %d-bit (step %.4f &deg;C) &mdash; CONFIG=0x%02X</p>",
           bits, step, cfg);
  sendString(USART, buf);
}

int main(void) {
  // Clocks & GPIO
  configureFlash();
  configureClock();
  gpioEnable(GPIO_PORT_A);
  gpioEnable(GPIO_PORT_B);
  gpioEnable(GPIO_PORT_C);

  // LED PB3
  pinMode(LED_PIN, GPIO_OUTPUT);
  digitalWrite(LED_PIN, 0);


  RCC->APB2ENR |= (RCC_APB2ENR_TIM15EN);
  initTIM(TIM15);

  // USART1 to ESP8266
  USART_TypeDef * USART = initUSART(USART1_ID, 125000);

  // SPI1 (CPOL=0, CPHA=1 for DS1722). Start slow-ish: BR=5 -> PCLK/64.
  initSPI(/*br=*/5, /*cpol=*/0, /*cpha=*/1);

  // Default DS1722 configuration: continuous, 12-bit
  setTempConfiguration(12);

  while (1) {
    // Read a single line like "/REQ:ledon\n"
    char request[BUFF_LEN] = "                                ";
    int idx = 0;
    while (inString(request, "\n") == -1) {
      while(!(USART->ISR & USART_ISR_RXNE)) { }
      if (idx < (BUFF_LEN-1)) request[idx++] = readChar(USART);
    }

    int led_status = updateLEDStatus(request);
    maybe_update_resolution(request);

    // Send full HTML page
    sendString(USART, webpageStart);
    sendString(USART, ledStr);

    sendString(USART, "<h2>LED Status</h2><p>");
    sendString(USART, (led_status ? "LED is on!" : "LED is off!"));
    sendString(USART, "</p>");

    resolutionControls(USART);

    // Temperature block (formats according to current resolution)
    print_temperature_block(USART);

    sendString(USART, webpageEnd);
  }
}
