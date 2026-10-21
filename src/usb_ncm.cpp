#include "usb_link.h"

#if defined(OUISPY_USB_NCM) && defined(OUISPY_USB_LINK)

#include <Arduino.h>
#include <esp_event.h>
#include <esp_netif.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/task.h>
#include <lwip/esp_netif_net_stack.h>
#include <lwip/sockets.h>
#include "esp32-hal-tinyusb.h"
#include "tusb.h"
#include "device/usbd_pvt.h"

namespace {

constexpr uint16_t kLinkPort = 4700;
constexpr uint8_t kHostMac[6] = {0x02, 0x4F, 0x53, 0x50, 0x59, 0x02};
constexpr uint8_t kBoardMac[6] = {0x02, 0x4F, 0x53, 0x50, 0x59, 0x01};
char hostMacStr[13];

esp_netif_t* ncmNetif = nullptr;
UsbLinkPort* port = nullptr;
volatile int clientFd = -1;

struct Packet {
    const void* data;
    uint16_t len;
    bool sent;
};

Packet* pending = nullptr;
SemaphoreHandle_t bufferSema = nullptr;
SemaphoreHandle_t txDone = nullptr;
SemaphoreHandle_t txLock = nullptr;

uint16_t ncmDescriptor(uint8_t* dst, uint8_t* itf) {
    uint8_t nameIdx = tinyusb_add_string_descriptor("OUI-SPY USB link");
    uint8_t macIdx = tinyusb_add_string_descriptor(hostMacStr);
    uint8_t notifEp = tinyusb_get_free_in_endpoint();
    uint8_t dataEp = tinyusb_get_free_duplex_endpoint();
    uint8_t desc[TUD_CDC_NCM_DESC_LEN] = {
        TUD_CDC_NCM_DESCRIPTOR(*itf, nameIdx, macIdx, (uint8_t)(0x80 | notifEp), 64, dataEp,
                               (uint8_t)(0x80 | dataEp), 64, CFG_TUD_NET_MTU, 50, 0)};
    *itf += 2;
    memcpy(dst, desc, sizeof(desc));
    return sizeof(desc);
}

struct NcmRegistrar {
    NcmRegistrar() {
        snprintf(hostMacStr, sizeof(hostMacStr), "%02X%02X%02X%02X%02X%02X", kHostMac[0], kHostMac[1],
                 kHostMac[2], kHostMac[3], kHostMac[4], kHostMac[5]);
        tinyusb_enable_interface(USB_INTERFACE_CUSTOM, TUD_CDC_NCM_DESC_LEN, ncmDescriptor);
    }
};

NcmRegistrar registrar;

void sendInUsbTask(void*) {
    if (xSemaphoreTake(bufferSema, 0) != pdTRUE) return;
    Packet* p = pending;
    if (p != nullptr) {
        p->sent = tud_network_can_xmit(p->len);
        if (p->sent) tud_network_xmit(p, p->len);
    }
    xSemaphoreGive(bufferSema);
    xSemaphoreGive(txDone);
}

esp_err_t netifTransmit(void*, void* buffer, size_t len) {
    if (!tud_mounted() || len == 0 || len > CFG_TUD_NET_MTU) return ESP_OK;
    xSemaphoreTake(txLock, portMAX_DELAY);
    Packet p = {buffer, (uint16_t)len, false};
    xSemaphoreTake(txDone, 0);
    pending = &p;
    xSemaphoreGive(bufferSema);
    usbd_defer_func(sendInUsbTask, nullptr, false);
    xSemaphoreTake(txDone, pdMS_TO_TICKS(100));
    xSemaphoreTake(bufferSema, portMAX_DELAY);
    pending = nullptr;
    xSemaphoreGive(txLock);
    return ESP_OK;
}

void l2Free(void*, void* buffer) {
    free(buffer);
}

size_t tcpWrite(const uint8_t* d, size_t n, void*) {
    int fd = clientFd;
    if (fd < 0) return 0;
    size_t sent = 0;
    while (sent < n) {
        int r = send(fd, d + sent, n - sent, 0);
        if (r <= 0) break;
        sent += (size_t)r;
    }
    return sent;
}

void linkStateTask(void*) {
    bool mounted = false;
    for (;;) {
        bool now = tud_mounted();
        if (now && !mounted) {
            tud_network_link_state(0, false);
            vTaskDelay(pdMS_TO_TICKS(500));
            tud_network_link_state(0, true);
            Serial.println("[NCM] host mounted, link up");
        } else if (!now && mounted) {
            Serial.println("[NCM] host gone");
        }
        mounted = now;
        vTaskDelay(pdMS_TO_TICKS(250));
    }
}

void tcpTask(void*) {
    int ls = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
    sockaddr_in addr = {};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(kLinkPort);
    addr.sin_addr.s_addr = inet_addr("192.168.7.1");
    if (ls < 0 || bind(ls, (sockaddr*)&addr, sizeof(addr)) != 0 || listen(ls, 1) != 0) {
        Serial.printf("[NCM] tcp listen failed errno=%d\n", errno);
        vTaskDelete(nullptr);
        return;
    }
    Serial.printf("[NCM] link server on 192.168.7.1:%u\n", (unsigned)kLinkPort);
    uint8_t buf[512];
    for (;;) {
        int c = accept(ls, nullptr, nullptr);
        if (c < 0) {
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;
        }
        int one = 1;
        setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
        timeval rt = {0, 10000};
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &rt, sizeof(rt));
        timeval st = {1, 0};
        setsockopt(c, SOL_SOCKET, SO_SNDTIMEO, &st, sizeof(st));
        clientFd = c;
        for (;;) {
            int n = recv(c, buf, sizeof(buf), 0);
            if (n > 0) {
                usbLinkPortFeed(port, buf, (size_t)n);
            } else if (n == 0 || (errno != EAGAIN && errno != EWOULDBLOCK)) {
                break;
            }
            usbLinkPortPump(port);
        }
        clientFd = -1;
        close(c);
        usbLinkPortDown(port);
    }
}

}

extern "C" bool tud_network_recv_cb(const uint8_t* src, uint16_t size) {
    if (ncmNetif != nullptr && size > 0) {
        void* copy = malloc(size);
        if (copy != nullptr) {
            memcpy(copy, src, size);
            esp_netif_receive(ncmNetif, copy, size, nullptr);
        }
    }
    tud_network_recv_renew();
    return true;
}

extern "C" uint16_t tud_network_xmit_cb(uint8_t* dst, void* ref, uint16_t arg) {
    Packet* p = (Packet*)ref;
    memcpy(dst, p->data, p->len);
    return p->len;
}

extern "C" void tud_network_init_cb(void) {}

void usbNcmInit(void) {
    bufferSema = xSemaphoreCreateBinary();
    txDone = xSemaphoreCreateBinary();
    txLock = xSemaphoreCreateMutex();
    if (bufferSema == nullptr || txDone == nullptr || txLock == nullptr) {
        Serial.println("[NCM] disabled: no memory for semaphores");
        return;
    }
    esp_netif_init();
    esp_event_loop_create_default();

    esp_netif_ip_info_t ip = {};
    ip.ip.addr = ipaddr_addr("192.168.7.1");
    ip.netmask.addr = ipaddr_addr("255.255.255.0");
    ip.gw.addr = ipaddr_addr("192.168.7.1");
    esp_netif_inherent_config_t base = {};
    base.flags = (esp_netif_flags_t)(ESP_NETIF_DHCP_SERVER | ESP_NETIF_FLAG_AUTOUP);
    base.ip_info = &ip;
    base.if_key = "ouispy_ncm";
    base.if_desc = "usb ncm link";
    base.route_prio = 5;
    esp_netif_driver_ifconfig_t driver = {};
    driver.handle = (void*)1;
    driver.transmit = netifTransmit;
    driver.driver_free_rx_buffer = l2Free;
    esp_netif_netstack_config stack = {};
    stack.lwip.init_fn = ethernetif_init;
    stack.lwip.input_fn = ethernetif_input;
    esp_netif_config_t cfg = {};
    cfg.base = &base;
    cfg.driver = &driver;
    cfg.stack = &stack;
    ncmNetif = esp_netif_new(&cfg);
    if (ncmNetif == nullptr) {
        Serial.println("[NCM] disabled: esp_netif_new failed");
        return;
    }
    esp_netif_set_mac(ncmNetif, (uint8_t*)kBoardMac);
    uint32_t lease = 60;
    esp_netif_dhcps_option(ncmNetif, ESP_NETIF_OP_SET, ESP_NETIF_IP_ADDRESS_LEASE_TIME, &lease, sizeof(lease));
    uint8_t offerRouter = 0;
    esp_netif_dhcps_option(ncmNetif, ESP_NETIF_OP_SET, ESP_NETIF_ROUTER_SOLICITATION_ADDRESS, &offerRouter,
                           sizeof(offerRouter));
    esp_netif_action_start(ncmNetif, nullptr, 0, nullptr);

    port = usbLinkPortCreate("ncm", tcpWrite, nullptr);
    if (port == nullptr) return;
    xTaskCreate(tcpTask, "ncmLink", 6144, nullptr, 3, nullptr);
    xTaskCreate(linkStateTask, "ncmState", 2560, nullptr, 2, nullptr);
}

#endif
