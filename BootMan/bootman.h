#pragma once
//BootMan bootloader header for C/C++

#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

#ifndef bool
#define bool uint8_t
#endif

#define BOOTLOADER_FUNCTION_LIST 0x3810

#pragma pack(push)
#pragma pack(1)

typedef struct tagFSINFO {
	uint32_t FATPos;
	uint32_t EntryPos;
	uint32_t RootDirEnd;
	uint32_t Clus0Pos;
	uint8_t SecPerClus;
	uint8_t FatType;
} FSINFO;

typedef struct tagFSINFO_EX {
	FSINFO fsinfo;
	uint8_t UseBlockAddress;
} FSINFO_EX;

typedef struct tagFILEINFO {
	uint32_t StartSector;
	uint32_t Length;
} FILEINFO;

#pragma pack(pop)

extern uint8_t(*flash_file)(const char *filename);
extern bool(*flash_page)(const uint8_t data[128], const void *addr);
extern uint8_t(*sd_init)(void);
extern uint8_t(*sd_readsect)(uint8_t *buffer, uint32_t sect, uint16_t start_byte, uint16_t byte_count, uint8_t use_block_address);
extern uint8_t(*getfsinfo)(uint8_t use_block_index, FSINFO *fsinfo);
extern FILEINFO(*findfile)(const char *filename, const FSINFO_EX *info);

#ifdef __cplusplus
}
#endif
