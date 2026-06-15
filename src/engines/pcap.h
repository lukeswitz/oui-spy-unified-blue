#ifndef PCAP_H
#define PCAP_H

#include "../engine_registry.h"
#include "../protocol.h"

extern const EngineCallbacks pcapCallbacks;

// Snapshot of current stats (caller copies to BLE buffer)
void pcapGetStats(PcapStats* out);

// Active capture mode (PCAP_MODE_WIFI / PCAP_MODE_BLE) while capturing, else 0xFF.
uint8_t pcapActiveMode(void);

// Begin a download session — opens the capture file for sequential reads.
// Returns true on success. file_size returned via PcapStats.
bool pcapBeginDownload(uint32_t* outSize, uint32_t* outCrc);

// Read the next chunk of capture data. Returns bytes copied (0=eof / error).
size_t pcapReadDownloadChunk(uint8_t* buf, size_t bufLen);

// Abort current download (close fd).
void pcapAbortDownload(void);

// Clear capture file
void pcapClearCapture(void);

#endif
