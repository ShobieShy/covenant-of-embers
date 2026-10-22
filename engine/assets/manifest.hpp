#pragma once
// Runtime reader for the cooker's manifest.json (BUILD_PLAN steps 6 + 11), parsed
// with simdjson. The game resolves assets by their source path (e.g.
// "assets/kenney/blaster-kit/Models/GLB format/blaster-a.glb"); resolve() verifies
// size + FNV-1a hash of the file and its dependencies before handing out a path, so
// a stale or hand-edited cooked dir fails loudly instead of rendering garbage.

#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace coe::assets {

struct ManifestEntry {
    std::string source;  // repo-relative source path, '/' separated
    std::string cooked;  // path relative to the cooked dir
    std::string type;    // gltf | glb | png | ogg | bin
    std::uint64_t bytes = 0;
    std::string hash;    // fnv1a64 hex
    std::vector<std::string> deps;  // sources this entry references
};

class CookedManifest {
public:
    // Reads <cookedDir>/manifest.json. Returns "" on success.
    std::string load(const std::filesystem::path& cookedDir);

    const ManifestEntry* find(std::string_view source) const;
    std::filesystem::path pathOf(const ManifestEntry& e) const { return dir_ / e.cooked; }
    // Size + hash check of one cooked file.
    std::string verify(const ManifestEntry& e) const;
    // find() + verify() the entry and (recursively) its deps; sets `out` to its cooked path.
    std::string resolve(std::string_view source, std::filesystem::path& out) const;

    const std::vector<ManifestEntry>& entries() const { return entries_; }
    const std::filesystem::path& dir() const { return dir_; }

private:
    std::string verifyTree(const ManifestEntry& e, int depth) const;

    std::filesystem::path dir_;
    std::vector<ManifestEntry> entries_;
};

}  // namespace coe::assets
