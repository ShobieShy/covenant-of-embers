// SPDX-License-Identifier: Apache-2.0
// Shared strict TOML readers for game data files (BUILD_PLAN step 17; moved out of
// game/world/level.cpp so levels, wieldables and later data tables validate alike).
//
// PRIVATE header of coe_game: it includes toml++ with TOML_EXCEPTIONS 0 (parse errors
// come back as toml::parse_result), and toml++ is a PRIVATE dependency of coe_game, so
// include it only from coe_game .cpp files, never from a public game/ header.
//
// Every reader reports the first problem as "<source>:<line>: <message>" through Ctx
// and returns false; later failures keep the first message.
#pragma once
#define TOML_EXCEPTIONS 0
#include <toml++/toml.hpp>

#include <glm/glm.hpp>

#include <filesystem>
#include <initializer_list>
#include <string>
#include <string_view>

namespace coe::game::data {

struct Ctx {
    std::string_view source;   // file name used in messages
    std::string err;           // first error, "" while everything is fine
    bool fail(const toml::node* at, const std::string& msg);   // always returns false
};

// Parses `text`; on a syntax error fills c.err ("<source>:<line>: TOML: ...") and returns false.
bool parseToml(Ctx& c, std::string_view text, toml::table& out);
// Reads a whole file; "" on success, else "<path>: cannot open <what>".
std::string readTextFile(const std::filesystem::path& path, std::string_view what, std::string& out);

bool readFloat(Ctx& c, const toml::node* n, const std::string& what, float& out);   // integer or float, finite
// readFloat + lo <= v <= hi (inclusive); the message names the range.
bool readFloatIn(Ctx& c, const toml::node* n, const std::string& what, float lo, float hi, float& out);
bool readVec3(Ctx& c, const toml::node* n, const std::string& what, glm::vec3& out);
bool readColor(Ctx& c, const toml::node* n, const std::string& what, glm::vec3& out);   // components in [0, 1]
bool readString(Ctx& c, const toml::node* n, const std::string& what, std::string& out);   // non-empty

// Rejects keys outside `allowed` so typos ("colour") fail instead of being ignored.
bool onlyKeys(Ctx& c, const toml::table& t, std::initializer_list<std::string_view> allowed, const std::string& where);
const toml::table* needTable(Ctx& c, const toml::table& root, std::string_view key);
// A non-empty [[key]] array of tables, else fails with "need at least one [[key]]".
const toml::array* needTableArray(Ctx& c, const toml::table& root, std::string_view key);

} // namespace coe::game::data
