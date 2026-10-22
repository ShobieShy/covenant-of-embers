// asset_cooker (BUILD_PLAN steps 6 + 11).
//
// Copies the glTF/GLB/PNG/OGG files it is given (files or directories,
// recursively) into an output folder, validating each one, and writes
// <out>/manifest.json listing every cooked file. PNG/OGG get container checks;
// glTF/GLB are parsed + validated with fastgltf (engine/assets/gltf_loader:
// accessors/bufferViews/buffers in range, attribute types, index ranges for
// embedded data, external .bin at least byteLength). Real conversion
// (KTX2/BasisU, meshoptimizer, navmesh bake, Pattern checks) comes later.
//
// Like an engine import step it records, per file, its source, cooked path,
// type, size, a content hash and its dependencies (external URIs referenced by
// glTF/GLB, which are cooked automatically so the cooked model stays loadable).
// The manifest is deterministic (sorted, no timestamps) so later steps can use
// it for incremental cooks and CI diffs.
//
// Usage: asset_cooker [--root DIR] [--out DIR] PATH...
//        asset_cooker --self-test
// Exit:  0 ok, 1 validation/IO error (nothing written to manifest), 2 usage.

#include "engine/assets/gltf_loader.hpp"
#include "engine/assets/hash.hpp"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <optional>
#include <random>
#include <span>
#include <set>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

namespace fs = std::filesystem;

namespace {

enum class Kind { Gltf, Glb, Png, Ogg };

const char* kind_name(Kind k) {
  switch (k) {
    case Kind::Gltf: return "gltf";
    case Kind::Glb: return "glb";
    case Kind::Png: return "png";
    case Kind::Ogg: return "ogg";
  }
  return "?";
}

std::optional<Kind> kind_of(const fs::path& p) {
  std::string e = p.extension().string();
  std::transform(e.begin(), e.end(), e.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  if (e == ".gltf") return Kind::Gltf;
  if (e == ".glb") return Kind::Glb;
  if (e == ".png") return Kind::Png;
  if (e == ".ogg") return Kind::Ogg;
  return std::nullopt;
}

bool read_file(const fs::path& p, std::string& out) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return false;
  std::ostringstream ss;
  ss << f.rdbuf();
  out = std::move(ss).str();
  return static_cast<bool>(f) || f.eof();
}

// FNV-1a 64 (engine/assets/hash.hpp, shared with the runtime manifest reader):
// change detection only, not a security hash.
std::string fnv1a64(std::string_view data) { return coe::assets::fnv1a64Hex(data.data(), data.size()); }

std::uint32_t le32(std::string_view d, std::size_t off) {
  return static_cast<std::uint32_t>(static_cast<unsigned char>(d[off])) |
         static_cast<std::uint32_t>(static_cast<unsigned char>(d[off + 1])) << 8 |
         static_cast<std::uint32_t>(static_cast<unsigned char>(d[off + 2])) << 16 |
         static_cast<std::uint32_t>(static_cast<unsigned char>(d[off + 3])) << 24;
}

// Full glTF parse + validation (fastgltf); collects external URIs, percent-decoded.
std::string inspect_gltf(std::string_view d, std::vector<coe::assets::GltfExternal>& uris) {
  coe::assets::GltfSummary summary;
  std::string why = coe::assets::inspectGltf(
      std::span(reinterpret_cast<const std::byte*>(d.data()), d.size()), summary);
  if (why.empty()) uris = std::move(summary.externals);
  return why;
}

// Validates the file and returns external URIs (glTF/GLB) via `uris`.
// Returns an empty string on success, else the reason.
std::string validate(Kind k, std::string_view d, std::vector<coe::assets::GltfExternal>& uris) {
  switch (k) {
    case Kind::Png: {
      static const char sig[8] = {'\x89', 'P', 'N', 'G', '\r', '\n', '\x1a', '\n'};
      if (d.size() < 33 || std::memcmp(d.data(), sig, 8) != 0) return "not a PNG (bad signature)";
      if (d.substr(12, 4) != "IHDR") return "PNG first chunk is not IHDR";
      if (d.find("IEND") == std::string_view::npos) return "PNG has no IEND chunk (truncated?)";
      return {};
    }
    case Kind::Ogg: {
      if (d.size() < 28 || d.substr(0, 4) != "OggS") return "not an Ogg stream (bad capture pattern)";
      if (d[4] != 0) return "unsupported Ogg stream version";
      return {};
    }
    case Kind::Glb: {
      if (d.size() < 20 || d.substr(0, 4) != "glTF") return "not a GLB (bad magic)";
      if (le32(d, 4) != 2) return "GLB version is not 2";
      if (le32(d, 8) != d.size()) return "GLB length field does not match file size (truncated?)";
      std::uint32_t json_len = le32(d, 12);
      if (d.substr(16, 4) != "JSON") return "GLB first chunk is not JSON";
      if (20ull + json_len > d.size()) return "GLB JSON chunk overruns file";
      std::string_view json = d.substr(20, json_len);
      if (json.find("\"asset\"") == std::string_view::npos) return "glTF JSON has no \"asset\" object";
      return inspect_gltf(d, uris);
    }
    case Kind::Gltf: {
      std::size_t i = 0;
      if (d.substr(0, 3) == "\xEF\xBB\xBF") i = 3;
      while (i < d.size() && std::isspace(static_cast<unsigned char>(d[i]))) ++i;
      if (i >= d.size() || d[i] != '{') return "glTF is not a JSON object";
      if (d.find("\"asset\"") == std::string_view::npos) return "glTF JSON has no \"asset\" object";
      return inspect_gltf(d, uris);
    }
  }
  return "unknown kind";
}

std::string json_escape(const std::string& s) {
  std::string o;
  for (unsigned char c : s) {
    switch (c) {
      case '"': o += "\\\""; break;
      case '\\': o += "\\\\"; break;
      case '\n': o += "\\n"; break;
      case '\t': o += "\\t"; break;
      case '\r': o += "\\r"; break;
      default:
        if (c < 0x20) {
          char b[8];
          std::snprintf(b, sizeof b, "\\u%04x", c);
          o += b;
        } else {
          o.push_back(static_cast<char>(c));
        }
    }
  }
  return o;
}

struct Entry {
  std::string source;  // relative to root, generic '/' separators
  Kind kind;
  std::uintmax_t bytes = 0;
  std::string hash;
  std::vector<std::string> deps;  // root-relative sources
};

bool is_within(const fs::path& child, const fs::path& parent) {
  auto rel = child.lexically_relative(parent);
  return !rel.empty() && *rel.begin() != "..";
}

struct Options {
  fs::path root = ".";
  fs::path out = "build/cooked";
  std::vector<fs::path> inputs;
};

int cook(const Options& opt, std::ostream& log) {
  std::error_code ec;
  const fs::path root = fs::weakly_canonical(opt.root, ec);
  if (ec || !fs::is_directory(root)) {
    log << "asset_cooker: root is not a directory: " << opt.root << "\n";
    return 1;
  }
  const fs::path out = fs::weakly_canonical(fs::absolute(opt.out), ec);
  if (is_within(out, root / "assets") || out == root || out == root / "assets") {
    log << "asset_cooker: refusing to cook into the source tree: " << out << "\n";
    return 1;
  }

  // Collect candidate files.
  std::set<fs::path> queue;
  std::size_t skipped = 0;
  for (const fs::path& in : opt.inputs) {
    fs::path p = fs::weakly_canonical(fs::absolute(in), ec);
    if (ec || !fs::exists(p)) {
      log << "asset_cooker: input not found: " << in << "\n";
      return 1;
    }
    if (!is_within(p, root)) {
      log << "asset_cooker: input outside root " << root << ": " << in << "\n";
      return 1;
    }
    if (fs::is_directory(p)) {
      for (auto it = fs::recursive_directory_iterator(p); it != fs::recursive_directory_iterator(); ++it) {
        if (it->path().filename().string().starts_with('.')) {
          if (it->is_directory()) it.disable_recursion_pending();
          continue;
        }
        if (!it->is_regular_file()) continue;
        if (kind_of(it->path())) queue.insert(it->path());
        else ++skipped;
      }
    } else if (kind_of(p)) {
      queue.insert(p);
    } else {
      log << "asset_cooker: unsupported file type (want .gltf/.glb/.png/.ogg): " << in << "\n";
      return 1;
    }
  }

  // Validate (and pull in glTF dependencies) before writing anything.
  std::map<std::string, Entry> entries;
  std::map<std::string, std::string> contents;
  int errors = 0;
  while (!queue.empty()) {
    fs::path p = *queue.begin();
    queue.erase(queue.begin());
    std::string rel = p.lexically_relative(root).generic_string();
    if (entries.count(rel)) continue;
    Kind k = *kind_of(p);
    std::string data;
    if (!read_file(p, data)) {
      log << "asset_cooker: cannot read " << rel << "\n";
      ++errors;
      continue;
    }
    std::vector<coe::assets::GltfExternal> uris;
    std::string why = validate(k, data, uris);
    if (!why.empty()) {
      log << "asset_cooker: invalid " << kind_name(k) << " " << rel << ": " << why << "\n";
      ++errors;
      continue;
    }
    Entry e{rel, k, data.size(), fnv1a64(data), {}};
    for (const coe::assets::GltfExternal& ext : uris) {
      const std::string& u = ext.path;  // already percent-decoded by fastgltf
      const std::string& dec = u;
      fs::path dep = (p.parent_path() / fs::path(dec)).lexically_normal();
      if (dec.find("://") != std::string::npos || fs::path(dec).is_absolute() || !is_within(dep, root)) {
        log << "asset_cooker: " << rel << " references a non-relative or out-of-root URI: " << u << "\n";
        ++errors;
        continue;
      }
      if (!fs::is_regular_file(dep)) {
        log << "asset_cooker: " << rel << " references missing file: " << u << "\n";
        ++errors;
        continue;
      }
      if (ext.minBytes && fs::file_size(dep, ec) < ext.minBytes) {
        log << "asset_cooker: " << rel << " buffer " << u << " is shorter than its byteLength " << ext.minBytes
            << "\n";
        ++errors;
        continue;
      }
      std::string dep_rel = dep.lexically_relative(root).generic_string();
      e.deps.push_back(dep_rel);
      if (kind_of(dep)) queue.insert(dep);
      else if (!entries.count(dep_rel) && !contents.count("bin:" + dep_rel)) {
        // .bin buffers etc.: copied verbatim, listed as type "bin".
        std::string bin;
        if (!read_file(dep, bin)) {
          log << "asset_cooker: cannot read " << dep_rel << "\n";
          ++errors;
          continue;
        }
        contents["bin:" + dep_rel] = std::move(bin);
      }
    }
    std::sort(e.deps.begin(), e.deps.end());
    e.deps.erase(std::unique(e.deps.begin(), e.deps.end()), e.deps.end());
    contents[rel] = std::move(data);
    entries.emplace(rel, std::move(e));
  }
  if (errors) {
    log << "asset_cooker: " << errors << " error(s); nothing written\n";
    return 1;
  }
  if (entries.empty()) {
    log << "asset_cooker: no .gltf/.glb/.png/.ogg files found in the given inputs\n";
    return 1;
  }

  // Write cooked files (layout mirrors the source tree) and the manifest.
  struct Row { std::string source, type, hash; std::uintmax_t bytes; std::vector<std::string> deps; };
  std::vector<Row> rows;
  for (auto& [key, data] : contents) {
    bool bin = key.rfind("bin:", 0) == 0;
    std::string rel = bin ? key.substr(4) : key;
    fs::path dst = out / fs::path(rel);
    fs::create_directories(dst.parent_path(), ec);
    std::ofstream f(dst, std::ios::binary | std::ios::trunc);
    f.write(data.data(), static_cast<std::streamsize>(data.size()));
    if (!f) {
      log << "asset_cooker: cannot write " << dst << "\n";
      return 1;
    }
    if (bin) rows.push_back({rel, "bin", fnv1a64(data), data.size(), {}});
    else {
      const Entry& e = entries.at(rel);
      rows.push_back({rel, kind_name(e.kind), e.hash, e.bytes, e.deps});
    }
  }
  std::sort(rows.begin(), rows.end(), [](const Row& a, const Row& b) { return a.source < b.source; });

  std::ostringstream js;
  js << "{\n  \"format\": \"coe-cooked-manifest\",\n  \"version\": 1,\n  \"hash\": \"fnv1a64\",\n";
  js << "  \"file_count\": " << rows.size() << ",\n  \"files\": [\n";
  for (std::size_t i = 0; i < rows.size(); ++i) {
    const Row& r = rows[i];
    js << "    {\"source\": \"" << json_escape(r.source) << "\", \"cooked\": \"" << json_escape(r.source)
       << "\", \"type\": \"" << r.type << "\", \"bytes\": " << r.bytes << ", \"hash\": \"" << r.hash
       << "\", \"deps\": [";
    for (std::size_t j = 0; j < r.deps.size(); ++j) js << (j ? ", " : "") << '"' << json_escape(r.deps[j]) << '"';
    js << "]}" << (i + 1 < rows.size() ? "," : "") << "\n";
  }
  js << "  ]\n}\n";
  fs::create_directories(out, ec);
  std::ofstream mf(out / "manifest.json", std::ios::binary | std::ios::trunc);
  mf << js.str();
  if (!mf) {
    log << "asset_cooker: cannot write manifest\n";
    return 1;
  }
  log << "asset_cooker: cooked " << rows.size() << " file(s) into " << out.string() << " (" << skipped
      << " unsupported file(s) skipped)\n";
  return 0;
}

// --- self-test: temp fixtures, removed afterwards -------------------------

int self_test() {
  fs::path tmp = fs::temp_directory_path() / ("coe_cooker_selftest_" + std::to_string(std::random_device{}()));
  fs::remove_all(tmp);
  fs::create_directories(tmp / "assets/pack/Textures");
  auto put = [&](const std::string& rel, const std::string& data) {
    fs::create_directories((tmp / rel).parent_path());
    std::ofstream(tmp / rel, std::ios::binary) << data;
  };
  auto glb = [](const std::string& json, int version = 2, int len_delta = 0) {
    std::string j = json;
    while (j.size() % 4) j.push_back(' ');
    std::string d = "glTF";
    auto u32 = [&](std::uint32_t v) { for (int i = 0; i < 4; ++i) d.push_back(static_cast<char>((v >> (8 * i)) & 0xff)); };
    u32(static_cast<std::uint32_t>(version));
    u32(static_cast<std::uint32_t>(12 + 8 + j.size() + len_delta));
    u32(static_cast<std::uint32_t>(j.size()));
    d += "JSON";
    d += j;
    return d;
  };
  const std::string png = std::string("\x89PNG\r\n\x1a\n\0\0\0\rIHDR", 16) + std::string(17, '\0') + "IEND\xae\x42\x60\x82";
  const std::string ogg = std::string("OggS\0", 5) + std::string(40, '\0');

  int fails = 0;
  auto expect = [&](const char* name, std::vector<fs::path> inputs, int want_rc, std::size_t want_files = 0) {
    fs::path out = tmp / "out";
    fs::remove_all(out);
    Options o;
    o.root = tmp;
    o.out = out;
    for (auto& i : inputs) o.inputs.push_back(tmp / i);
    std::ostringstream log;
    int rc = cook(o, log);
    bool ok = rc == want_rc;
    if (ok && rc == 0) {
      std::string m;
      ok = read_file(out / "manifest.json", m) &&
           m.find("\"file_count\": " + std::to_string(want_files) + ",") != std::string::npos;
    }
    if (ok && rc != 0) ok = !fs::exists(out / "manifest.json");
    std::cout << (ok ? "PASS " : "FAIL ") << name << "\n";
    if (!ok) {
      std::cout << "  rc=" << rc << " log: " << log.str();
      ++fails;
    }
  };

  put("assets/pack/Textures/colormap.png", png);
  put("assets/pack/a.glb", glb(R"({"asset":{"version":"2.0"},"images":[{"uri":"Textures/colormap.png"}]})"));
  put("assets/pack/b.ogg", ogg);
  put("assets/pack/readme.txt", "skip me");
  expect("valid dir cooks glb+png+ogg, skips txt", {"assets/pack"}, 0, 3);
  expect("glb pulls in its texture dependency", {"assets/pack/a.glb"}, 0, 2);
  put("assets/pack/c.gltf", R"({"asset":{"version":"2.0"},"buffers":[{"uri":"c%20data.bin","byteLength":4}]})");
  put("assets/pack/c data.bin", "abcd");
  expect("gltf with %-encoded .bin buffer", {"assets/pack/c.gltf"}, 0, 2);

  put("assets/bad1/x.png", "not a png at all, definitely not");
  expect("bad PNG signature rejected", {"assets/bad1"}, 1);
  put("assets/bad2/x.png", png.substr(0, png.size() - 8));
  expect("truncated PNG rejected", {"assets/bad2"}, 1);
  put("assets/bad3/x.glb", glb(R"({"asset":{"version":"2.0"}})", 2, 8));
  expect("GLB length mismatch rejected", {"assets/bad3"}, 1);
  put("assets/bad4/x.glb", glb(R"({"asset":{"version":"1.0"}})", 1));
  expect("GLB v1 rejected", {"assets/bad4"}, 1);
  put("assets/bad5/x.glb", glb(R"({"asset":{"version":"2.0"},"images":[{"uri":"missing.png"}]})"));
  expect("GLB missing dependency rejected", {"assets/bad5"}, 1);
  put("assets/bad6/x.ogg", "RIFF....WAVEfmt this is not ogg data");
  expect("bad Ogg rejected", {"assets/bad6"}, 1);
  put("assets/bad7/x.gltf", "[1,2,3]");
  expect("glTF that is not an object rejected", {"assets/bad7"}, 1);
  put("assets/bad8/x.glb", glb(R"({"asset":{"version":"2.0"},"images":[{"uri":"../../../etc/passwd"}]})"));
  expect("out-of-root URI rejected", {"assets/bad8"}, 1);

  // fastgltf-backed checks (step 11): one triangle, positions + uint16 indices.
  auto tri_buffer = [](std::uint16_t last_index) {
    std::string b;
    const float pos[9] = {0, 0, 0, 1, 0, 0, 0, 1, 0};
    b.append(reinterpret_cast<const char*>(pos), sizeof pos);
    const std::uint16_t idx[3] = {0, 1, last_index};
    b.append(reinterpret_cast<const char*>(idx), sizeof idx);
    return b;  // 42 bytes
  };
  auto base64 = [](const std::string& in) {
    static const char* t = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string o;
    for (std::size_t i = 0; i < in.size(); i += 3) {
      std::uint32_t n = static_cast<unsigned char>(in[i]) << 16;
      if (i + 1 < in.size()) n |= static_cast<unsigned char>(in[i + 1]) << 8;
      if (i + 2 < in.size()) n |= static_cast<unsigned char>(in[i + 2]);
      o.push_back(t[(n >> 18) & 63]);
      o.push_back(t[(n >> 12) & 63]);
      o.push_back(i + 1 < in.size() ? t[(n >> 6) & 63] : '=');
      o.push_back(i + 2 < in.size() ? t[n & 63] : '=');
    }
    return o;
  };
  auto tri_gltf = [](const std::string& uri, int pos_count = 3, int idx_view_len = 6,
                     const char* attr = "POSITION") {
    return std::string(R"({"asset":{"version":"2.0"},"buffers":[{"uri":")") + uri +
           R"(","byteLength":42}],"bufferViews":[{"buffer":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":)" +
           std::to_string(idx_view_len) + R"(}],"accessors":[{"bufferView":0,"componentType":5126,"count":)" +
           std::to_string(pos_count) +
           R"(,"type":"VEC3","min":[0,0,0],"max":[1,1,0]},{"bufferView":1,"componentType":5123,"count":3,"type":"SCALAR"}],)"
           R"("meshes":[{"primitives":[{"attributes":{")" + attr +
           R"(":0},"indices":1}]}],"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}],"scene":0})";
  };
  const std::string data_uri = "data:application/octet-stream;base64," + base64(tri_buffer(2));
  put("assets/tri/ok.gltf", tri_gltf(data_uri));
  expect("valid triangle glTF (data: URI) cooks", {"assets/tri/ok.gltf"}, 0, 1);
  put("assets/tri_ext/t.gltf", tri_gltf("t.bin"));
  put("assets/tri_ext/t.bin", tri_buffer(2));
  expect("valid triangle glTF with external .bin cooks", {"assets/tri_ext/t.gltf"}, 0, 2);
  put("assets/bad9/x.gltf", "{\"asset\": {\"version\": \"2.0\"}, ");
  expect("malformed glTF JSON rejected", {"assets/bad9"}, 1);
  put("assets/bad10/x.gltf", tri_gltf(data_uri, 4));
  expect("accessor overrunning its bufferView rejected", {"assets/bad10"}, 1);
  put("assets/bad11/x.gltf", tri_gltf(data_uri, 3, 10));
  expect("bufferView overrunning its buffer rejected", {"assets/bad11"}, 1);
  put("assets/bad12/x.gltf", tri_gltf("x.bin"));
  put("assets/bad12/x.bin", tri_buffer(2).substr(0, 20));
  expect("external .bin shorter than byteLength rejected", {"assets/bad12/x.gltf"}, 1);
  put("assets/bad13/x.gltf", tri_gltf("data:application/octet-stream;base64," + base64(tri_buffer(7))));
  expect("index value out of range rejected", {"assets/bad13"}, 1);
  put("assets/bad14/x.gltf", tri_gltf(data_uri, 3, 6, "NORMAL"));
  expect("primitive without POSITION rejected", {"assets/bad14"}, 1);
  put("assets/bad15/x.gltf", tri_gltf("https://example.com/x.bin"));
  expect("remote buffer URI rejected", {"assets/bad15"}, 1);

  put("assets/empty/notes.txt", "x");
  expect("no cookable files is an error", {"assets/empty"}, 1);
  expect("unsupported single file rejected", {"assets/pack/readme.txt"}, 1);
  expect("missing input rejected", {"assets/nope"}, 1);
  {
    Options o;
    o.root = tmp;
    o.out = tmp / "assets/out";
    o.inputs = {tmp / "assets/pack"};
    std::ostringstream log;
    bool ok = cook(o, log) == 1 && !fs::exists(tmp / "assets/out");
    std::cout << (ok ? "PASS " : "FAIL ") << "refuses to cook into assets/\n";
    fails += ok ? 0 : 1;
  }

  fs::remove_all(tmp);
  std::cout << (fails ? "self-test FAILED: " : "self-test ok: ") << fails << " failure(s)\n";
  return fails ? 1 : 0;
}

void usage() {
  std::cerr << "usage: asset_cooker [--root DIR] [--out DIR] PATH...\n"
               "       asset_cooker --self-test\n"
               "Copies + validates .gltf/.glb/.png/.ogg files (dirs are walked) into OUT\n"
               "(default build/cooked) and writes OUT/manifest.json. ROOT defaults to '.'.\n";
}

}  // namespace

int main(int argc, char** argv) {
  Options opt;
  for (int i = 1; i < argc; ++i) {
    std::string_view a = argv[i];
    if (a == "--self-test") return self_test();
    if (a == "-h" || a == "--help") { usage(); return 0; }
    if ((a == "--root" || a == "--out") && i + 1 < argc) {
      (a == "--root" ? opt.root : opt.out) = argv[++i];
    } else if (a.starts_with("--")) {
      usage();
      return 2;
    } else {
      opt.inputs.emplace_back(argv[i]);
    }
  }
  if (opt.inputs.empty()) { usage(); return 2; }
  try {
    return cook(opt, std::cerr);
  } catch (const std::exception& e) {
    std::cerr << "asset_cooker: " << e.what() << "\n";
    return 1;
  }
}
