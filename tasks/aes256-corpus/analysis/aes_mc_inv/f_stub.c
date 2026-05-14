typedef unsigned char uint8_t;
uint8_t f(uint8_t x) { return (x & 0x80) ? ((x << 1) ^ 0x1b) : (x << 1); }
