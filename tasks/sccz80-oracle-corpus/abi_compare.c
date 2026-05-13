/*
 * Per-function ABI attribute comparison for SDCC under z88dk.
 *
 * For each of four function shapes (1-arg byte, 2-arg byte, 1-arg
 * void-return, no-args), compile four variants:
 *   _def       — no annotation (zsdcc default, sdcccall 0, stack args)
 *   _fastcall  — __z88dk_fastcall (single arg passed in DEHL subset)
 *   _callee    — __z88dk_callee   (called fn cleans the stack)
 *   _sdccc1    — __sdcccall(1)    (SDCC register ABI per-function)
 *
 * Note constraints from SDCC/z88dk docs:
 *   - __z88dk_fastcall: at most ONE argument total. 2-arg shapes
 *     compile with it only if combined with stack-passing for the
 *     remaining args (or by reducing to 1 arg).
 *   - __sdcccall(1) is the per-function form of --sdcccall 1.
 *
 * Compile with zcc default flags (no --sdcccall 1 global), so the
 * baseline is sdcccall 0; the attributes opt individual functions
 * into different ABIs.
 */

#include <stdint.h>

extern volatile uint8_t flag;

/* ===== Shape 1: uint8_t f(uint8_t) — 1-arg unary ===== */

/* SDCC syntax: attribute goes AFTER the parameter list, like __naked. */

uint8_t inc_def(uint8_t x) { return x + 1; }
uint8_t inc_fastcall(uint8_t x) __z88dk_fastcall;
uint8_t inc_fastcall(uint8_t x) __z88dk_fastcall { return x + 1; }
uint8_t inc_callee(uint8_t x) __z88dk_callee;
uint8_t inc_callee(uint8_t x) __z88dk_callee   { return x + 1; }
uint8_t inc_sdccc1(uint8_t x) __sdcccall(1);
uint8_t inc_sdccc1(uint8_t x) __sdcccall(1)    { return x + 1; }

/* ===== Shape 2: uint8_t f(uint8_t, uint8_t) — 2-arg binary =====
 * __z88dk_fastcall not legal with >1 arg, skip that variant. */

uint8_t add_def(uint8_t a, uint8_t b) { return a + b; }
uint8_t add_callee(uint8_t a, uint8_t b) __z88dk_callee;
uint8_t add_callee(uint8_t a, uint8_t b) __z88dk_callee { return a + b; }
uint8_t add_sdccc1(uint8_t a, uint8_t b) __sdcccall(1);
uint8_t add_sdccc1(uint8_t a, uint8_t b) __sdcccall(1)  { return a + b; }

/* ===== Shape 3: void f(uint8_t) — 1-arg void return =====
 * Writes to volatile global so the store can't be DCE'd. */

void store_def(uint8_t v) { flag = v; }
void store_fastcall(uint8_t v) __z88dk_fastcall;
void store_fastcall(uint8_t v) __z88dk_fastcall { flag = v; }
void store_callee(uint8_t v) __z88dk_callee;
void store_callee(uint8_t v) __z88dk_callee   { flag = v; }
void store_sdccc1(uint8_t v) __sdcccall(1);
void store_sdccc1(uint8_t v) __sdcccall(1)    { flag = v; }

/* ===== Shape 4: uint16_t f(uint16_t) — 1-arg 16-bit, exercises
 * the wider register slot (HL under fastcall, DE under sdcccall(1)
 * return). */

uint16_t neg_def(uint16_t x) { return ~x; }
uint16_t neg_fastcall(uint16_t x) __z88dk_fastcall;
uint16_t neg_fastcall(uint16_t x) __z88dk_fastcall { return ~x; }
uint16_t neg_callee(uint16_t x) __z88dk_callee;
uint16_t neg_callee(uint16_t x) __z88dk_callee   { return ~x; }
uint16_t neg_sdccc1(uint16_t x) __sdcccall(1);
uint16_t neg_sdccc1(uint16_t x) __sdcccall(1)    { return ~x; }

/* ===== Combination: sdcccall(1) + callee ===== */

uint8_t inc_s1_callee(uint8_t x) __sdcccall(1) __z88dk_callee;
uint8_t inc_s1_callee(uint8_t x) __sdcccall(1) __z88dk_callee { return x + 1; }

uint8_t add_s1_callee(uint8_t a, uint8_t b) __sdcccall(1) __z88dk_callee;
uint8_t add_s1_callee(uint8_t a, uint8_t b) __sdcccall(1) __z88dk_callee { return a + b; }

/* ===== Call sites — measure caller cost per ABI =====
 * Each caller does N=3 sequential calls into the same flavour.
 * Comparing per-call overhead across flavours requires comparing
 * caller bytes / 3. */

void call_def(void)      { flag = inc_def(1); flag = inc_def(2); flag = inc_def(3); }
void call_fastcall(void) { flag = inc_fastcall(1); flag = inc_fastcall(2); flag = inc_fastcall(3); }
void call_callee(void)   { flag = inc_callee(1); flag = inc_callee(2); flag = inc_callee(3); }
void call_sdccc1(void)   { flag = inc_sdccc1(1); flag = inc_sdccc1(2); flag = inc_sdccc1(3); }
void call_s1_callee(void){ flag = inc_s1_callee(1); flag = inc_s1_callee(2); flag = inc_s1_callee(3); }
