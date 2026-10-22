// Covenant of Embers - minimal entry point (M0 skeleton).
// SPDX-License-Identifier: Apache-2.0
#include <cstdint>
#include <cstdio>
#ifdef COE_HAS_VULKAN
#include <vulkan/vulkan.h>
#endif

int main() {
    std::puts("Covenant of Embers v0.0.1");
#ifdef COE_HAS_VULKAN
    std::uint32_t version = 0;
    if (vkEnumerateInstanceVersion(&version) == VK_SUCCESS) {
        std::printf("Vulkan loader: %u.%u.%u\n", VK_API_VERSION_MAJOR(version),
                    VK_API_VERSION_MINOR(version), VK_API_VERSION_PATCH(version));
    }
#endif
    return 0;
}
