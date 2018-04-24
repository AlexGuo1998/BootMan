#pragma once
//BootMan bootloader header for C/C++

#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#else
#include <stdbool.h>
#endif

#define BOOTLOADER_FUNCTION_LIST 0x3810

#define flash_file (*((uint8_t(*)(const char *filename))                  (BOOTLOADER_FUNCTION_LIST)))
#define flash_page (*((bool   (*)(const uint8_t data[128], uint16_t addr))(BOOTLOADER_FUNCTION_LIST + 2)))
#define sd_init    (*((uint8_t(*)(void))                                  (BOOTLOADER_FUNCTION_LIST + 4)))

#undef BOOTLOADER_FUNCTION_LIST

#ifdef __cplusplus
}
#endif
