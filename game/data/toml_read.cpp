// SPDX-License-Identifier: Apache-2.0
#include "game/data/toml_read.hpp"

#include <cmath>
#include <fstream>
#include <sstream>

namespace coe::game::data {

bool Ctx::fail(const toml::node* at, const std::string& msg) {
    if (!err.empty()) return false;
    std::ostringstream o;
    o << source;
    if (at && at->source().begin) o << ':' << at->source().begin.line;
    o << ": " << msg;
    err = o.str();
    return false;
}

bool parseToml(Ctx& c, std::string_view text, toml::table& out) {
    toml::parse_result parsed = toml::parse(text, c.source);
    if (!parsed) {
        std::ostringstream o;
        o << c.source << ':' << parsed.error().source().begin.line << ": TOML: " << parsed.error().description();
        if (c.err.empty()) c.err = o.str();
        return false;
    }
    out = std::move(parsed).table();
    return true;
}

std::string readTextFile(const std::filesystem::path& path, std::string_view what, std::string& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return path.string() + ": cannot open " + std::string(what);
    std::ostringstream ss;
    ss << f.rdbuf();
    out = ss.str();
    return {};
}

bool readFloat(Ctx& c, const toml::node* n, const std::string& what, float& out) {
    if (!n || !(n->is_floating_point() || n->is_integer())) return c.fail(n, what + " must be a number");
    const double v = n->is_integer() ? double(n->as_integer()->get()) : n->as_floating_point()->get();
    if (!std::isfinite(v)) return c.fail(n, what + " must be finite");
    out = float(v);
    return true;
}

bool readFloatIn(Ctx& c, const toml::node* n, const std::string& what, float lo, float hi, float& out) {
    if (!readFloat(c, n, what, out)) return false;
    if (out < lo || out > hi) {
        std::ostringstream o;
        o << what << " must be in [" << lo << ", " << hi << "]";
        return c.fail(n, o.str());
    }
    return true;
}

bool readVec3(Ctx& c, const toml::node* n, const std::string& what, glm::vec3& out) {
    const toml::array* a = n ? n->as_array() : nullptr;
    if (!a || a->size() != 3) return c.fail(n, what + " must be an array of 3 numbers");
    for (int i = 0; i < 3; ++i)
        if (!readFloat(c, a->get(size_t(i)), what, out[i])) return false;
    return true;
}

bool readColor(Ctx& c, const toml::node* n, const std::string& what, glm::vec3& out) {
    if (!readVec3(c, n, what, out)) return false;
    for (int i = 0; i < 3; ++i)
        if (out[i] < 0.0f || out[i] > 1.0f) return c.fail(n, what + " components must be in [0, 1]");
    return true;
}

bool readString(Ctx& c, const toml::node* n, const std::string& what, std::string& out) {
    if (!n || !n->is_string()) return c.fail(n, what + " must be a string");
    out = n->as_string()->get();
    if (out.empty()) return c.fail(n, what + " must not be empty");
    return true;
}

bool onlyKeys(Ctx& c, const toml::table& t, std::initializer_list<std::string_view> allowed, const std::string& where) {
    for (auto&& [k, v] : t) {
        bool known = false;
        for (std::string_view a : allowed) known = known || a == k.str();
        if (!known) return c.fail(&v, where + ": unknown key '" + std::string(k.str()) + "'");
    }
    return true;
}

const toml::table* needTable(Ctx& c, const toml::table& root, std::string_view key) {
    const toml::node* n = root.get(key);
    if (!n || !n->is_table()) { c.fail(n ? n : &root, "missing [" + std::string(key) + "] table"); return nullptr; }
    return n->as_table();
}

const toml::array* needTableArray(Ctx& c, const toml::table& root, std::string_view key) {
    const toml::node* n = root.get(key);
    const toml::array* a = n ? n->as_array() : nullptr;
    if (!a || a->empty() || !a->is_array_of_tables()) {
        c.fail(n ? n : &root, "need at least one [[" + std::string(key) + "]]");
        return nullptr;
    }
    return a;
}

} // namespace coe::game::data
