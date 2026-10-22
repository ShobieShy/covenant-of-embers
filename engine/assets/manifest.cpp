#include "engine/assets/manifest.hpp"

#include "engine/assets/hash.hpp"

#include <simdjson.h>

#include <fstream>
#include <iterator>

namespace coe::assets {
namespace {

// Cooked paths come from a file on disk: refuse anything that escapes the cooked dir.
bool safeRelative(const std::string& p) {
    if (p.empty()) return false;
    const std::filesystem::path path(p);
    if (path.is_absolute() || path.has_root_name() || path.has_root_directory()) return false;
    for (const auto& part : path)
        if (part == "..") return false;
    return true;
}

}  // namespace

std::string CookedManifest::load(const std::filesystem::path& cookedDir) {
    dir_ = cookedDir;
    entries_.clear();
    const auto file = cookedDir / "manifest.json";
    simdjson::padded_string json;
    if (simdjson::padded_string::load(file.string()).get(json) != simdjson::SUCCESS)
        return "cannot read " + file.string() + " (run the `cook` target)";
    simdjson::dom::parser parser;
    simdjson::dom::element root;
    if (auto e = parser.parse(json).get(root); e != simdjson::SUCCESS)
        return file.string() + ": malformed JSON: " + simdjson::error_message(e);

    std::string_view format, hash;
    std::uint64_t version = 0, fileCount = 0;
    simdjson::dom::array files;
    if (root["format"].get_string().get(format) || format != "coe-cooked-manifest")
        return file.string() + ": not a coe-cooked-manifest";
    if (root["version"].get_uint64().get(version) || version != 1)
        return file.string() + ": unsupported manifest version";
    if (root["hash"].get_string().get(hash) || hash != "fnv1a64")
        return file.string() + ": unsupported hash";
    if (root["files"].get_array().get(files) || root["file_count"].get_uint64().get(fileCount))
        return file.string() + ": missing files/file_count";

    for (simdjson::dom::element f : files) {
        ManifestEntry e;
        std::string_view s, c, t, h;
        simdjson::dom::array deps;
        if (f["source"].get_string().get(s) || f["cooked"].get_string().get(c) ||
            f["type"].get_string().get(t) || f["bytes"].get_uint64().get(e.bytes) ||
            f["hash"].get_string().get(h) || f["deps"].get_array().get(deps)) {
            entries_.clear();
            return file.string() + ": malformed entry #" + std::to_string(entries_.size());
        }
        e.source = s;
        e.cooked = c;
        e.type = t;
        e.hash = h;
        for (simdjson::dom::element d : deps) {
            std::string_view ds;
            if (d.get_string().get(ds)) {
                entries_.clear();
                return file.string() + ": non-string dep in " + e.source;
            }
            e.deps.emplace_back(ds);
        }
        if (!safeRelative(e.cooked)) {
            const std::string bad = e.cooked;
            entries_.clear();
            return file.string() + ": unsafe cooked path '" + bad + "'";
        }
        entries_.push_back(std::move(e));
    }
    if (fileCount != entries_.size()) {
        entries_.clear();
        return file.string() + ": file_count does not match files[]";
    }
    return {};
}

const ManifestEntry* CookedManifest::find(std::string_view source) const {
    for (const auto& e : entries_)
        if (e.source == source) return &e;
    return nullptr;
}

std::string CookedManifest::verify(const ManifestEntry& e) const {
    const auto path = pathOf(e);
    std::ifstream in(path, std::ios::binary);
    if (!in) return "cooked file missing: " + path.string();
    const std::string data{std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
    if (data.size() != e.bytes)
        return "cooked file " + path.string() + " is " + std::to_string(data.size()) + " bytes, manifest says " +
               std::to_string(e.bytes) + " (re-run `cook`)";
    if (fnv1a64Hex(data.data(), data.size()) != e.hash)
        return "cooked file " + path.string() + " hash mismatch (re-run `cook`)";
    return {};
}

std::string CookedManifest::verifyTree(const ManifestEntry& e, int depth) const {
    if (depth > 16) return "dependency chain too deep at " + e.source;
    if (auto why = verify(e); !why.empty()) return why;
    for (const auto& d : e.deps) {
        const ManifestEntry* dep = find(d);
        if (!dep) return e.source + " depends on " + d + ", which is not in the manifest";
        if (auto why = verifyTree(*dep, depth + 1); !why.empty()) return why;
    }
    return {};
}

std::string CookedManifest::resolve(std::string_view source, std::filesystem::path& out) const {
    const ManifestEntry* e = find(source);
    if (!e) return "asset not in cooked manifest: " + std::string(source);
    if (auto why = verifyTree(*e, 0); !why.empty()) return why;
    out = pathOf(*e);
    return {};
}

}  // namespace coe::assets
