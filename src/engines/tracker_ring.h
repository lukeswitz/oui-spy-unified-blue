#ifndef ENGINE_TRACKER_RING_H
#define ENGINE_TRACKER_RING_H

#include <stdint.h>

#define TRACKER_RING_OK          0x00
#define TRACKER_RING_BUSY        0x01
#define TRACKER_RING_NO_CONNECT  0x02
#define TRACKER_RING_NO_SERVICE  0x03
#define TRACKER_RING_WRITE_FAIL  0x04

typedef void (*TrackerRingDoneFn)(const uint8_t mac[6], uint8_t status, uint8_t protocol);

bool trackerRingStart(const uint8_t mac[6], uint8_t addrType, TrackerRingDoneFn done);

#endif
