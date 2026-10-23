// SPDX-License-Identifier: Apache-2.0
#include "engine/render/camera.hpp"

#include <cmath>
#include <glm/gtc/matrix_transform.hpp>

namespace coe {

glm::vec3 Camera::forward() const {
    const float cp = std::cos(pitch);
    return {-std::sin(yaw) * cp, std::sin(pitch), -std::cos(yaw) * cp};
}

glm::mat4 Camera::view() const {
    // Inverse of T(position) * Ry(yaw) * Rx(pitch).
    glm::mat4 v = glm::rotate(glm::mat4(1.0f), -pitch, glm::vec3(1, 0, 0));
    v = glm::rotate(v, -yaw, glm::vec3(0, 1, 0));
    return glm::translate(v, -position);
}

glm::mat4 Camera::projection(float aspect) const {
    const float f = 1.0f / std::tan(glm::radians(fovYDeg) * 0.5f);
    glm::mat4 p(0.0f);                 // glm is column-major: p[column][row]
    p[0][0] = f / aspect;
    p[1][1] = -f;                      // Vulkan clip Y points down
    p[2][3] = -1.0f;                   // w = -z_view (distance in front of the camera)
    p[3][2] = nearZ;                   // depth = near / distance: 1 at near, -> 0 at infinity
    return p;
}

float Camera::lookScaleForFov(float fovYDeg, float hipFovYDeg) {
    return std::tan(glm::radians(fovYDeg) * 0.5f) / std::tan(glm::radians(hipFovYDeg) * 0.5f);
}

} // namespace coe
