#include "bootman.h"
//BootMan bootloader function pointers for C/C++

uint8_t(*flash_file)(const char *filename) = BOOTLOADER_FUNCTION_LIST + 0;
bool(*flash_page)(const uint8_t data[128], uint16_t addr) = BOOTLOADER_FUNCTION_LIST + 2;
uint8_t(*sd_init)(void) = BOOTLOADER_FUNCTION_LIST + 4;
uint8_t(*sd_readsect)(uint8_t *buffer, uint32_t sect, uint16_t start_byte, uint16_t byte_count, uint8_t use_block_address) = BOOTLOADER_FUNCTION_LIST + 6;
uint8_t(*getfsinfo)(uint8_t use_block_index, FSINFO *fsinfo) = BOOTLOADER_FUNCTION_LIST + 8;
FILEINFO(*findfile)(const char *filename, const FSINFO_EX *info) = BOOTLOADER_FUNCTION_LIST + 10;
