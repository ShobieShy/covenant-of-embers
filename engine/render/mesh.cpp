// SPDX-License-Identifier: Apache-2.0
#include "engine/render/mesh.hpp"

#include <cstddef>

namespace coe {

VertexLayout vertexLayout() {
    using assets::Vertex;
    VertexLayout l;
    l.binding = {0, sizeof(Vertex), VK_VERTEX_INPUT_RATE_VERTEX};
    l.attributes[0] = {0, 0, VK_FORMAT_R32G32B32_SFLOAT, offsetof(Vertex, position)};
    l.attributes[1] = {1, 0, VK_FORMAT_R32G32B32_SFLOAT, offsetof(Vertex, normal)};
    l.attributes[2] = {2, 0, VK_FORMAT_R32G32B32A32_SFLOAT, offsetof(Vertex, color)};
    return l;
}

} // namespace coe
