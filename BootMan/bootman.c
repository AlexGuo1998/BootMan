#include "bootman.h"
//BootMan bootloader function pointers for C/C++

uint8_t(*bl_flashfile)(const char *filename) = (uint8_t(*)(const char *))(BOOTLOADER_FUNCTION_LIST + 0);
bool(*bl_flashpage)(const uint8_t data[128], const void *addr) = (bool(*)(const uint8_t *, const void *))(BOOTLOADER_FUNCTION_LIST + 2);
uint8_t(*bl_sdinit)(void) = (uint8_t(*)(void))(BOOTLOADER_FUNCTION_LIST + 4);
uint8_t(*bl_sdreadsect)(uint8_t *buffer, uint32_t sect, uint16_t start_byte, uint16_t byte_count, uint8_t use_block_address) = (uint8_t(*)(uint8_t *, uint32_t, uint16_t, uint16_t, uint8_t))(BOOTLOADER_FUNCTION_LIST + 6);
uint8_t(*bl_getfsinfo)(uint8_t use_block_index, FSINFO *fsinfo) = (uint8_t(*)(uint8_t, FSINFO *))(BOOTLOADER_FUNCTION_LIST + 8);
FILEINFO(*bl_findfile)(const char *filename, const FSINFO_EX *info) = (FILEINFO(*)(const char *, const FSINFO_EX *))(BOOTLOADER_FUNCTION_LIST + 10);
