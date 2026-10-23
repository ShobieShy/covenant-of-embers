// SPDX-License-Identifier: Apache-2.0
#include "game/enemies/enemy.hpp"

#include "game/data/toml_read.hpp"

#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/quaternion.hpp>

#include <algorithm>
#include <array>

namespace coe::game {
namespace {
using data::Ctx;

std::string elementChoices() {
    std::string out;
    for (Element e : kAllElements) out += std::string(out.empty() ? "" : ", ") + elementName(e);
    return out;
}

bool readSize(Ctx& c, const toml::node* n, const std::string& what, glm::vec3& out) {
    if (!data::readVec3(c, n, what, out)) return false;
    if (out.x <= 0.0f || out.y <= 0.0f || out.z <= 0.0f || out.x > 50.0f || out.y > 50.0f || out.z > 50.0f)
        return c.fail(n, what + " components must be in (0, 50] m");
    return true;
}

bool parseDef(Ctx& c, const toml::table& t, std::size_t index, EnemyDef& d) {
    const std::string where = "enemy #" + std::to_string(index + 1);
    if (!data::onlyKeys(c, t, {"id", "name", "affinity", "max_health", "size", "color", "resist", "weak_point"}, where))
        return false;
    if (!data::readString(c, t.get("id"), where + " id", d.id)) return false;
    for (char ch : d.id)
        if (!((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_'))
            return c.fail(t.get("id"), where + ": id '" + d.id + "' must be lower_snake_case [a-z0-9_]");
    const std::string w = "enemy '" + d.id + "'";
    std::string aff;
    if (!data::readString(c, t.get("name"), w + " name", d.name) ||
        !data::readString(c, t.get("affinity"), w + " affinity", aff))
        return false;
    const auto e = parseElement(aff);
    if (!e) return c.fail(t.get("affinity"), w + ": unknown affinity '" + aff + "' (expected " + elementChoices() + ")");
    d.affinity = *e;
    if (!data::readFloatIn(c, t.get("max_health"), w + " max_health", 1.0f, 100000.0f, d.maxHealth) ||
        !readSize(c, t.get("size"), w + " size", d.size) || !data::readColor(c, t.get("color"), w + " color", d.color))
        return false;
    if (const toml::node* r = t.get("resist")) {
        const toml::table* rt = r->as_table();
        if (!rt) return c.fail(r, w + " resist must be a table { <element> = 0..1 }");
        for (const auto& [key, value] : *rt) {
            const auto el = parseElement(key.str());
            if (!el)
                return c.fail(&value, w + ": unknown resist element '" + std::string(key.str()) + "' (expected " +
                                          elementChoices() + ")");
            // Stored as authored (gear will sum past the cap); resolveHit clamps to 60 %.
            if (!data::readFloatIn(c, &value, w + " resist." + std::string(key.str()), 0.0f, 1.0f,
                                   d.resist[std::size_t(*el)]))
                return false;
        }
    }
    if (const toml::node* wp = t.get("weak_point")) {
        const toml::table* wt = wp->as_table();
        if (!wt) return c.fail(wp, w + " weak_point must be a table { offset, size }");
        WeakPointDef def;
        if (!data::onlyKeys(c, *wt, {"offset", "size"}, w + " weak_point") ||
            !data::readVec3(c, wt->get("offset"), w + " weak_point offset", def.offset) ||
            !readSize(c, wt->get("size"), w + " weak_point size", def.size))
            return false;
        d.weakPoint = def;
    }
    return true;
}

glm::mat4 boxModel(const glm::vec3& feet, float yawDeg, const glm::vec3& localCenter, const glm::vec3& size) {
    glm::mat4 m = glm::translate(glm::mat4(1.0f), feet);
    m = glm::rotate(m, glm::radians(yawDeg), glm::vec3(0.0f, 1.0f, 0.0f));
    m = glm::translate(m, localCenter);
    return glm::scale(m, size);
}

physics::BodyHandle addHitbox(physics::PhysicsWorld& w, const glm::vec3& feet, float yawDeg, const glm::vec3& localCenter,
                              const glm::vec3& size) {
    const glm::quat q = glm::angleAxis(glm::radians(yawDeg), glm::vec3(0.0f, 1.0f, 0.0f));
    physics::BoxDesc d;
    d.center = feet + q * localCenter;
    d.halfExtents = size * 0.5f;
    d.rotation = q;
    d.layer = physics::Layers::Enemy;
    return w.addKinematicBox(d);
}
} // namespace

const EnemyDef* EnemyTable::find(std::string_view id) const {
    for (const EnemyDef& d : defs)
        if (d.id == id) return &d;
    return nullptr;
}

std::string parseEnemies(std::string_view text, std::string_view sourceName, EnemyTable& out) {
    out = {};
    Ctx c{sourceName, {}};
    toml::table root;
    if (!data::parseToml(c, text, root)) return c.err;
    if (!data::onlyKeys(c, root, {"enemy"}, "top level")) return c.err;
    const toml::array* list = data::needTableArray(c, root, "enemy");
    if (!list) return c.err;
    for (std::size_t i = 0; i < list->size(); ++i) {
        EnemyDef d;
        if (!parseDef(c, *list->get(i)->as_table(), i, d)) { out = {}; return c.err; }
        if (out.find(d.id)) { c.fail(list->get(i), "duplicate enemy id '" + d.id + "'"); out = {}; return c.err; }
        out.defs.push_back(std::move(d));
    }
    return {};
}

std::string loadEnemies(const std::filesystem::path& path, EnemyTable& out) {
    out = {};
    std::string text;
    if (std::string err = data::readTextFile(path, "enemies file", text); !err.empty()) return err;
    return parseEnemies(text, path.filename().string(), out);
}

glm::mat4 Enemy::bodyModel() const {
    return boxModel(feet, yawDeg, glm::vec3(0.0f, def->size.y * 0.5f, 0.0f), def->size);
}

glm::mat4 Enemy::weakPointModel() const {
    return boxModel(feet, yawDeg, def->weakPoint->offset, def->weakPoint->size);
}

EnemySystem::EnemySystem(physics::PhysicsWorld& world, const ElementTable& elements) : world_(world), elements_(elements) {}

EnemySystem::~EnemySystem() {
    for (Enemy& e : enemies_) {
        world_.removeBody(e.body);
        world_.removeBody(e.weakPoint);
    }
}

std::uint32_t EnemySystem::spawn(const EnemyDef& def, const glm::vec3& feet, float yawDeg) {
    Enemy e;
    e.id = nextId_++;
    e.def = &def;
    e.feet = feet;
    e.yawDeg = yawDeg;
    e.health = def.maxHealth;
    e.body = addHitbox(world_, feet, yawDeg, glm::vec3(0.0f, def.size.y * 0.5f, 0.0f), def.size);
    if (def.weakPoint) e.weakPoint = addHitbox(world_, feet, yawDeg, def.weakPoint->offset, def.weakPoint->size);
    enemies_.push_back(e);
    return e.id;
}

const Enemy* EnemySystem::find(std::uint32_t id) const {
    for (const Enemy& e : enemies_)
        if (e.id == id) return &e;
    return nullptr;
}

const Enemy* EnemySystem::byBody(physics::BodyHandle body) const {
    if (!body.valid()) return nullptr;
    for (const Enemy& e : enemies_)
        if (!e.dead && (e.body == body || e.weakPoint == body)) return &e;
    return nullptr;
}

std::size_t EnemySystem::alive() const {
    return std::size_t(std::count_if(enemies_.begin(), enemies_.end(), [](const Enemy& e) { return !e.dead; }));
}

std::optional<EnemyHit> EnemySystem::applyHit(const ProjectileHit& hit) {
    const Enemy* found = byBody(hit.body);
    if (!found) return std::nullopt;
    Enemy& e = enemies_[std::size_t(found - enemies_.data())];
    EnemyHit out;
    out.enemy = e.id;
    out.weakPoint = e.weakPoint.valid() && hit.body == e.weakPoint;
    out.point = hit.point;
    out.element = hit.element;
    out.result = resolveHit(hit.damage, hit.element, DamageTarget{e.def->affinity, e.def->resist, out.weakPoint}, elements_);
    out.healthBefore = e.health;
    e.health = std::max(0.0f, e.health - out.result.amount);
    out.healthAfter = e.health;
    e.damageTaken += out.healthBefore - out.healthAfter;
    ++e.hits;
    e.flash = kFlashTime;
    if (e.health <= 0.0f) {
        out.killed = true;
        kill(e, hit.element);
    }
    return out;
}

void EnemySystem::kill(Enemy& e, Element element) {
    e.dead = true;
    e.health = 0.0f;
    world_.removeBody(e.body);
    world_.removeBody(e.weakPoint);
    e.body = e.weakPoint = {};
    deaths_.push_back({e.id, e.def, e.feet, element});
    ++kills_;
}

void EnemySystem::tick(float dt) {
    for (Enemy& e : enemies_) e.flash = std::max(0.0f, e.flash - dt);
}

std::vector<EnemyDeath> EnemySystem::takeDeaths() {
    std::vector<EnemyDeath> out;
    out.swap(deaths_);
    return out;
}

void EnemySystem::draws(MeshId cube, std::vector<DrawItem>& out) const {
    for (const Enemy& e : enemies_) {
        if (e.dead) continue;
        // Hit flash: lerp toward white for kFlashTime after each hit.
        const float f = std::clamp(e.flash / kFlashTime, 0.0f, 1.0f);
        const glm::vec3 body = glm::mix(e.def->color, glm::vec3(1.0f), f * 0.7f);
        out.push_back({cube, e.bodyModel(), glm::vec4(body, 1.0f)});
        if (e.def->weakPoint) {
            const glm::vec3 head = glm::mix(glm::min(e.def->color * 1.6f + 0.15f, glm::vec3(1.0f)), glm::vec3(1.0f), f * 0.7f);
            out.push_back({cube, e.weakPointModel(), glm::vec4(head, 1.0f)});
        }
    }
}

} // namespace coe::game
