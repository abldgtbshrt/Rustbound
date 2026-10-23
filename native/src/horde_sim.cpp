#include "horde_sim.h"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

// Must match FLASH_TIME / SEPARATION_* in horde_sim_gd.gd.
static constexpr float FLASH_TIME = 0.12f;
static constexpr int SEPARATION_NEIGHBORS = 6;
static constexpr float SEPARATION_FORCE = 8.0f;
static constexpr float STEER_RATE = 5.0f;

void HordeSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "capacity", "cell_size", "arena_half_extent"), &HordeSim::setup);
	ClassDB::bind_method(D_METHOD("set_types", "radius", "speed", "color", "model_scale"), &HordeSim::set_types);
	ClassDB::bind_method(D_METHOD("backend_name"), &HordeSim::backend_name);

	ClassDB::bind_method(D_METHOD("get_count"), &HordeSim::get_count);
	ClassDB::bind_method(D_METHOD("get_capacity"), &HordeSim::get_capacity);
	ClassDB::bind_method(D_METHOD("spawn", "type", "at", "hp"), &HordeSim::spawn);
	ClassDB::bind_method(D_METHOD("clear"), &HordeSim::clear);
	ClassDB::bind_method(D_METHOD("compact"), &HordeSim::compact);
	ClassDB::bind_method(D_METHOD("is_alive", "i"), &HordeSim::is_alive);
	ClassDB::bind_method(D_METHOD("alive_count"), &HordeSim::alive_count);

	ClassDB::bind_method(D_METHOD("get_pos", "i"), &HordeSim::get_pos);
	ClassDB::bind_method(D_METHOD("set_pos", "i", "p"), &HordeSim::set_pos);
	ClassDB::bind_method(D_METHOD("get_vel", "i"), &HordeSim::get_vel);
	ClassDB::bind_method(D_METHOD("set_vel", "i", "v"), &HordeSim::set_vel);
	ClassDB::bind_method(D_METHOD("get_hp", "i"), &HordeSim::get_hp);
	ClassDB::bind_method(D_METHOD("set_hp", "i", "v"), &HordeSim::set_hp);
	ClassDB::bind_method(D_METHOD("get_type", "i"), &HordeSim::get_type);
	ClassDB::bind_method(D_METHOD("get_flash", "i"), &HordeSim::get_flash);
	ClassDB::bind_method(D_METHOD("get_cooldown", "i"), &HordeSim::get_cooldown);
	ClassDB::bind_method(D_METHOD("set_cooldown", "i", "v"), &HordeSim::set_cooldown);
	ClassDB::bind_method(D_METHOD("get_slow_t", "i"), &HordeSim::get_slow_t);
	ClassDB::bind_method(D_METHOD("get_slow_mult", "i"), &HordeSim::get_slow_mult);
	ClassDB::bind_method(D_METHOD("get_burn_t", "i"), &HordeSim::get_burn_t);
	ClassDB::bind_method(D_METHOD("get_burn_dps", "i"), &HordeSim::get_burn_dps);

	ClassDB::bind_method(D_METHOD("damage", "i", "amount", "knockback"), &HordeSim::damage);
	ClassDB::bind_method(D_METHOD("apply_slow", "i", "mult", "duration"), &HordeSim::apply_slow);
	ClassDB::bind_method(D_METHOD("apply_burn", "i", "dps", "duration"), &HordeSim::apply_burn);
	ClassDB::bind_method(D_METHOD("damage_radius", "origin", "radius", "amount", "knockback"), &HordeSim::damage_radius);
	ClassDB::bind_method(D_METHOD("take_kills"), &HordeSim::take_kills);

	ClassDB::bind_method(D_METHOD("query_radius", "origin", "radius"), &HordeSim::query_radius);
	ClassDB::bind_method(D_METHOD("query_segment", "origin", "dir", "reach", "width"), &HordeSim::query_segment);
	ClassDB::bind_method(D_METHOD("find_nearest", "origin", "max_range", "forward", "cos_half_arc"), &HordeSim::find_nearest);

	ClassDB::bind_method(D_METHOD("rebuild_grid"), &HordeSim::rebuild_grid);
	ClassDB::bind_method(D_METHOD("step", "delta", "target", "robot_radius", "chase"), &HordeSim::step);
	ClassDB::bind_method(D_METHOD("get_contacts"), &HordeSim::get_contacts);
	ClassDB::bind_method(D_METHOD("get_contact_dirs"), &HordeSim::get_contact_dirs);
	ClassDB::bind_method(D_METHOD("resolve_contacts"), &HordeSim::resolve_contacts);
	ClassDB::bind_method(D_METHOD("upload_multimeshes", "multimeshes", "target"), &HordeSim::upload_multimeshes);
	ClassDB::bind_method(D_METHOD("get_type_buffer", "type", "target"), &HordeSim::get_type_buffer);
}

// --- Setup -------------------------------------------------------------------

void HordeSim::setup(int p_capacity, float p_cell_size, float p_arena_half_extent) {
	capacity = std::max(p_capacity, 0);
	cell_size = std::max(p_cell_size, 0.1f);
	arena_half = std::max(p_arena_half_extent, 1.0f);
	count = 0;
	pos.assign(capacity, Vector3());
	vel.assign(capacity, Vector3());
	hp.assign(capacity, 0.0f);
	flash.assign(capacity, 0.0f);
	cooldown.assign(capacity, 0.0f);
	slow_t.assign(capacity, 0.0f);
	slow_mult.assign(capacity, 1.0f);
	burn_t.assign(capacity, 0.0f);
	burn_dps.assign(capacity, 0.0f);
	type.assign(capacity, 0);

	grid_min = (int)std::floor(-arena_half / cell_size) - 1;
	int grid_max = (int)std::floor(arena_half / cell_size) + 1;
	grid_n = grid_max - grid_min + 1;
	cell_start.assign(grid_n * grid_n + 1, 0);
	cell_items.assign(capacity, 0);
	cell_of.assign(capacity, 0);
	grid_dirty = true;

	type_buffers.clear();
	type_counts.clear();
	kills.clear();
	contacts.clear();
	contact_dirs.clear();
	contact_push.clear();
}

void HordeSim::set_types(const PackedFloat32Array &p_radius, const PackedFloat32Array &p_speed, const PackedColorArray &p_color, const PackedFloat32Array &p_model_scale) {
	int n = (int)p_radius.size();
	t_radius.resize(n);
	t_speed.resize(n);
	t_color.resize(n);
	t_shape.resize(n);
	t_lift.resize(n);
	max_radius = 0.0f;
	const Basis tip(Vector3(1, 0, 0), -Math_PI * 0.5);
	for (int t = 0; t < n; t++) {
		float r = p_radius[t];
		t_radius[t] = r;
		t_speed[t] = t < p_speed.size() ? p_speed[t] : 0.0f;
		t_color[t] = t < p_color.size() ? p_color[t] : Color(1, 1, 1);
		float ms = t < p_model_scale.size() ? p_model_scale[t] : 0.0f;
		if (ms > 0.0f) {
			// Authored model: faces -Z already; its origin is at its feet.
			t_shape[t] = Basis::from_scale(Vector3(ms, ms, ms));
			t_lift[t] = -r;
		} else {
			float s = r * 2.0f;
			// Prism points +Y; tip it forward so the wedge "noses" at the robot.
			t_shape[t] = tip * Basis::from_scale(Vector3(s, s * 1.2f, s * 0.8f));
			t_lift[t] = 0.0f;
		}
		max_radius = std::max(max_radius, r);
	}
}

// --- Rows --------------------------------------------------------------------

int HordeSim::spawn(int p_type, const Vector3 &p_at, float p_hp) {
	if (count >= capacity || p_type < 0 || p_type >= (int)t_radius.size()) {
		return -1;
	}
	int i = count++;
	pos[i] = Vector3(p_at.x, t_radius[p_type], p_at.z);
	vel[i] = Vector3();
	hp[i] = p_hp;
	flash[i] = 0.0f;
	cooldown[i] = 0.0f;
	slow_t[i] = 0.0f;
	slow_mult[i] = 1.0f;
	burn_t[i] = 0.0f;
	burn_dps[i] = 0.0f;
	type[i] = p_type;
	grid_dirty = true;
	return i;
}

void HordeSim::clear() {
	count = 0;
	kills.clear();
	contacts.clear();
	contact_dirs.clear();
	contact_push.clear();
	grid_dirty = true;
}

// Removes dead rows by swapping in the last row. Call at the start of a frame
// so indices stay stable for everyone else during the frame.
void HordeSim::compact() {
	int i = 0;
	bool changed = false;
	while (i < count) {
		if (hp[i] <= 0.0f) {
			count--;
			pos[i] = pos[count];
			vel[i] = vel[count];
			hp[i] = hp[count];
			flash[i] = flash[count];
			cooldown[i] = cooldown[count];
			slow_t[i] = slow_t[count];
			slow_mult[i] = slow_mult[count];
			burn_t[i] = burn_t[count];
			burn_dps[i] = burn_dps[count];
			type[i] = type[count];
			changed = true;
		} else {
			i++;
		}
	}
	if (changed) {
		grid_dirty = true;
	}
}

int HordeSim::alive_count() const {
	int n = 0;
	for (int i = 0; i < count; i++) {
		n += hp[i] > 0.0f ? 1 : 0;
	}
	return n;
}

// --- Combat ------------------------------------------------------------------

bool HordeSim::damage(int i, float p_amount, const Vector3 &p_knockback) {
	if (!is_alive(i)) {
		return false;
	}
	hp[i] -= p_amount;
	flash[i] = FLASH_TIME;
	vel[i] += p_knockback;
	return hp[i] <= 0.0f;
}

void HordeSim::apply_slow(int i, float p_mult, float p_duration) {
	if (!is_alive(i)) {
		return;
	}
	if (slow_t[i] <= 0.0f || p_mult < slow_mult[i]) {
		slow_mult[i] = Math::clamp(p_mult, 0.05f, 1.0f);
	}
	slow_t[i] = std::max(slow_t[i], p_duration);
}

void HordeSim::apply_burn(int i, float p_dps, float p_duration) {
	if (!is_alive(i)) {
		return;
	}
	burn_dps[i] = std::max(burn_t[i] > 0.0f ? burn_dps[i] : 0.0f, p_dps);
	burn_t[i] = std::max(burn_t[i], p_duration);
}

// Damages every live enemy within `radius` (XZ, edge-inclusive) of `origin`,
// with 50% falloff at the edge, pushing them outward. Returns hits; kills are
// queued for take_kills().
int HordeSim::damage_radius(const Vector3 &p_origin, float p_radius, float p_amount, float p_knockback) {
	PackedInt32Array near = query_radius(p_origin, p_radius + 1.0f);
	int hits = 0;
	for (int k = 0; k < near.size(); k++) {
		int i = near[k];
		Vector3 to = pos[i] - p_origin;
		to.y = 0.0f;
		float d = to.length();
		float reach = p_radius + type_radius(type[i]);
		if (d > reach) {
			continue;
		}
		float falloff = Math::lerp(1.0f, 0.5f, Math::clamp(d / reach, 0.0f, 1.0f));
		if (damage(i, p_amount * falloff, (to / std::max(d, 0.01f)) * p_knockback)) {
			kills.push_back(i);
		}
		hits++;
	}
	return hits;
}

PackedInt32Array HordeSim::take_kills() {
	PackedInt32Array out;
	out.resize((int64_t)kills.size());
	for (size_t k = 0; k < kills.size(); k++) {
		out.set((int64_t)k, kills[k]);
	}
	kills.clear();
	return out;
}

// --- Grid --------------------------------------------------------------------

int HordeSim::cell_x(float x) const {
	int c = (int)std::floor(x / cell_size);
	return std::clamp(c, grid_min, grid_min + grid_n - 1);
}

int HordeSim::cell_z(float z) const {
	return cell_x(z);
}

void HordeSim::rebuild_grid() {
	const int cells = grid_n * grid_n;
	std::fill(cell_start.begin(), cell_start.end(), 0);
	for (int i = 0; i < count; i++) {
		int c = (cell_x(pos[i].x) - grid_min) * grid_n + (cell_z(pos[i].z) - grid_min);
		cell_of[i] = c;
		cell_start[c + 1]++;
	}
	for (int c = 0; c < cells; c++) {
		cell_start[c + 1] += cell_start[c];
	}
	// Stable fill keeps indices ascending inside each cell.
	cell_fill.assign(cell_start.begin(), cell_start.end() - 1);
	for (int i = 0; i < count; i++) {
		cell_items[cell_fill[cell_of[i]]++] = i;
	}
	grid_dirty = false;
}

// --- Queries -----------------------------------------------------------------

PackedInt32Array HordeSim::query_radius(const Vector3 &p_origin, float p_radius) {
	ensure_grid();
	PackedInt32Array out;
	const float r2 = p_radius * p_radius;
	const int x0 = cell_x(p_origin.x - p_radius), x1 = cell_x(p_origin.x + p_radius);
	const int z0 = cell_z(p_origin.z - p_radius), z1 = cell_z(p_origin.z + p_radius);
	for (int cx = x0; cx <= x1; cx++) {
		for (int cz = z0; cz <= z1; cz++) {
			int c = (cx - grid_min) * grid_n + (cz - grid_min);
			for (int k = cell_start[c]; k < cell_start[c + 1]; k++) {
				int i = cell_items[k];
				if (hp[i] <= 0.0f) {
					continue;
				}
				float dx = pos[i].x - p_origin.x;
				float dz = pos[i].z - p_origin.z;
				if (dx * dx + dz * dz <= r2) {
					out.push_back(i);
				}
			}
		}
	}
	return out;
}

// Live enemies touched by a beam from `origin` along `dir` (XZ) for `reach`
// metres, `width` wide (plus each enemy's radius).
PackedInt32Array HordeSim::query_segment(const Vector3 &p_origin, const Vector3 &p_dir, float p_reach, float p_width) {
	ensure_grid();
	PackedInt32Array out;
	const Vector3 tip = p_origin + p_dir * p_reach;
	const float pad = p_width + max_radius;
	const int x0 = cell_x(std::min(p_origin.x, tip.x) - pad), x1 = cell_x(std::max(p_origin.x, tip.x) + pad);
	const int z0 = cell_z(std::min(p_origin.z, tip.z) - pad), z1 = cell_z(std::max(p_origin.z, tip.z) + pad);
	for (int cx = x0; cx <= x1; cx++) {
		for (int cz = z0; cz <= z1; cz++) {
			int c = (cx - grid_min) * grid_n + (cz - grid_min);
			for (int k = cell_start[c]; k < cell_start[c + 1]; k++) {
				int i = cell_items[k];
				if (hp[i] <= 0.0f) {
					continue;
				}
				Vector3 to = pos[i] - p_origin;
				to.y = 0.0f;
				float along = to.dot(p_dir);
				if (along < 0.0f || along > p_reach) {
					continue;
				}
				if ((to - p_dir * along).length() <= p_width + type_radius(type[i])) {
					out.push_back(i);
				}
			}
		}
	}
	return out;
}

// Nearest live enemy within range whose direction lies inside a cone around
// `forward` (cos_half_arc = cos(arc/2); pass -1 for any direction). Searches
// grid rings outward and stops once no closer enemy can exist.
int HordeSim::find_nearest(const Vector3 &p_origin, float p_max_range, const Vector3 &p_forward, float p_cos_half_arc) {
	ensure_grid();
	if (count == 0) {
		return -1;
	}
	int best = -1;
	float best_d2 = p_max_range * p_max_range;
	float fx = p_forward.x, fz = p_forward.z;
	float fl = std::sqrt(fx * fx + fz * fz);
	if (fl > 0.0f) {
		fx /= fl;
		fz /= fl;
	}
	const bool use_arc = p_cos_half_arc > -1.0f;
	const int ox = (int)std::floor(p_origin.x / cell_size);
	const int oz = (int)std::floor(p_origin.z / cell_size);
	const int max_ring = (int)std::ceil(p_max_range / cell_size) + 1;
	const int gmax = grid_min + grid_n - 1;

	for (int r = 0; r <= max_ring; r++) {
		if (r >= 2) {
			float gap = (r - 1) * cell_size; // closest any point in ring r can be
			if (gap * gap > best_d2) {
				break;
			}
		}
		for (int cx = ox - r; cx <= ox + r; cx++) {
			if (cx < grid_min || cx > gmax) {
				continue;
			}
			const bool edge_col = (cx == ox - r || cx == ox + r);
			for (int cz = oz - r; cz <= oz + r; cz += (edge_col || r == 0) ? 1 : 2 * r) {
				if (cz < grid_min || cz > gmax) {
					continue;
				}
				int c = (cx - grid_min) * grid_n + (cz - grid_min);
				for (int k = cell_start[c]; k < cell_start[c + 1]; k++) {
					int i = cell_items[k];
					if (hp[i] <= 0.0f) {
						continue;
					}
					float dx = pos[i].x - p_origin.x;
					float dz = pos[i].z - p_origin.z;
					float d2 = dx * dx + dz * dz;
					if (d2 >= best_d2 && !(d2 == best_d2 && best >= 0 && i < best)) {
						continue;
					}
					if (use_arc && d2 > 0.0001f) {
						float inv = 1.0f / std::sqrt(d2);
						if ((dx * fx + dz * fz) * inv < p_cos_half_arc) {
							continue;
						}
					}
					best = i;
					best_d2 = d2;
				}
			}
		}
	}
	return best;
}

// --- Per frame ---------------------------------------------------------------

void HordeSim::step(float p_delta, const Vector3 &p_target, float p_robot_radius, bool p_chase) {
	rebuild_grid();
	contacts.clear();
	contact_dirs.clear();
	contact_push.clear();
	const float steer = Math::clamp(STEER_RATE * p_delta, 0.0f, 1.0f);
	const int gmax = grid_min + grid_n - 1;

	for (int i = 0; i < count; i++) {
		if (hp[i] <= 0.0f) {
			continue;
		}
		const int t = type[i];
		const float rad = type_radius(t);
		Vector3 p = pos[i];
		Vector3 to(p_target.x - p.x, 0.0f, p_target.z - p.z);
		float d = to.length();

		Vector3 desired;
		if (p_chase && d > 0.001f) {
			desired = to / d * (t < (int)t_speed.size() ? t_speed[t] : 0.0f);
		}

		// Separation from up to 6 overlapping neighbors in this and adjacent cells.
		Vector3 sep;
		int checked = 0;
		const int cx = cell_x(p.x), cz = cell_z(p.z);
		for (int ox = -1; ox <= 1 && checked < SEPARATION_NEIGHBORS; ox++) {
			int nx = cx + ox;
			if (nx < grid_min || nx > gmax) {
				continue;
			}
			for (int oz = -1; oz <= 1 && checked < SEPARATION_NEIGHBORS; oz++) {
				int nz = cz + oz;
				if (nz < grid_min || nz > gmax) {
					continue;
				}
				int c = (nx - grid_min) * grid_n + (nz - grid_min);
				for (int k = cell_start[c]; k < cell_start[c + 1]; k++) {
					int j = cell_items[k];
					if (j == i || hp[j] <= 0.0f) {
						continue;
					}
					float dx = p.x - pos[j].x;
					float dz = p.z - pos[j].z;
					float min_d = rad + type_radius(type[j]);
					float dl = dx * dx + dz * dz;
					if (dl < min_d * min_d && dl > 0.000001f) {
						float len = std::sqrt(dl);
						float push = (min_d - len) * SEPARATION_FORCE / len;
						sep.x += dx * push;
						sep.z += dz * push;
						if (++checked >= SEPARATION_NEIGHBORS) {
							break;
						}
					}
				}
			}
		}

		if (slow_t[i] > 0.0f) {
			slow_t[i] -= p_delta;
			desired *= slow_mult[i];
		}
		if (burn_t[i] > 0.0f) {
			burn_t[i] -= p_delta;
			hp[i] -= burn_dps[i] * p_delta; // no hit flash for damage over time
			if (hp[i] <= 0.0f) {
				kills.push_back(i);
				continue;
			}
		}
		Vector3 v = vel[i].lerp(desired, steer) + sep * p_delta;
		p += v * p_delta;
		p.x = Math::clamp(p.x, -arena_half, arena_half);
		p.z = Math::clamp(p.z, -arena_half, arena_half);
		p.y = rad;

		// Contact: queued for the robot to judge (ram, crush, armor); the
		// overlap is pushed out in resolve_contacts().
		float contact = rad + p_robot_radius;
		if (p_chase && d < contact) {
			contacts.push_back(i);
			contact_dirs.push_back(-to);
			contact_push.push_back(d > 0.001f ? -(to / d) * (contact - d) : Vector3());
		}
		if (cooldown[i] > 0.0f) {
			cooldown[i] -= p_delta;
		}
		if (flash[i] > 0.0f) {
			flash[i] -= p_delta;
		}
		pos[i] = p;
		vel[i] = v;
	}
}

PackedInt32Array HordeSim::get_contacts() const {
	PackedInt32Array out;
	out.resize((int64_t)contacts.size());
	for (size_t k = 0; k < contacts.size(); k++) {
		out.set((int64_t)k, contacts[k]);
	}
	return out;
}

PackedVector3Array HordeSim::get_contact_dirs() const {
	PackedVector3Array out;
	out.resize((int64_t)contact_dirs.size());
	for (size_t k = 0; k < contact_dirs.size(); k++) {
		out.set((int64_t)k, contact_dirs[k]);
	}
	return out;
}

void HordeSim::resolve_contacts() {
	for (size_t k = 0; k < contacts.size(); k++) {
		int i = contacts[k];
		if (valid(i)) {
			pos[i] += contact_push[k];
		}
	}
	contacts.clear();
	contact_dirs.clear();
	contact_push.clear();
}

// MultiMesh buffers for TRANSFORM_3D + colors, one per type: per instance
// 12 floats (3x4 row-major basis | origin) then RGBA, in enemy index order.
void HordeSim::fill_type_buffers(const Vector3 &p_target) {
	const int ntypes = (int)t_radius.size();
	type_buffers.resize(ntypes);
	type_counts.assign(ntypes, 0);
	for (int t = 0; t < ntypes; t++) {
		if (type_buffers[t].size() != capacity * 16) {
			type_buffers[t].resize(capacity * 16);
		}
	}
	std::vector<float *> w(ntypes);
	for (int t = 0; t < ntypes; t++) {
		w[t] = type_buffers[t].ptrw();
	}
	const Color burn_col(1.0f, 0.5f, 0.1f), slow_col(0.4f, 0.7f, 1.0f), white(1, 1, 1);
	for (int i = 0; i < count; i++) {
		const int t = type[i];
		if (t < 0 || t >= ntypes) {
			continue;
		}
		const Vector3 &p = pos[i];
		Vector3 look(p_target.x - p.x, 0.0f, p_target.z - p.z);
		Basis b;
		if (look.length_squared() > 0.0001f) {
			b = Basis::looking_at(look.normalized(), Vector3(0, 1, 0));
		}
		b = b * t_shape[t];
		float *o = w[t] + type_counts[t]++ * 16;
		o[0] = b.rows[0].x;
		o[1] = b.rows[0].y;
		o[2] = b.rows[0].z;
		o[3] = p.x;
		o[4] = b.rows[1].x;
		o[5] = b.rows[1].y;
		o[6] = b.rows[1].z;
		o[7] = p.y + t_lift[t];
		o[8] = b.rows[2].x;
		o[9] = b.rows[2].y;
		o[10] = b.rows[2].z;
		o[11] = p.z;
		Color col = t_color[t];
		if (burn_t[i] > 0.0f) {
			col = col.lerp(burn_col, 0.5f);
		} else if (slow_t[i] > 0.0f) {
			col = col.lerp(slow_col, 0.5f);
		}
		if (flash[i] > 0.0f) {
			col = white;
		}
		o[12] = col.r;
		o[13] = col.g;
		o[14] = col.b;
		o[15] = col.a;
	}
}

PackedInt32Array HordeSim::upload_multimeshes(const Array &p_multimeshes, const Vector3 &p_target) {
	fill_type_buffers(p_target);
	PackedInt32Array counts;
	counts.resize((int64_t)type_counts.size());
	RenderingServer *rs = RenderingServer::get_singleton();
	for (int t = 0; t < (int)type_counts.size(); t++) {
		counts.set(t, type_counts[t]);
		if (t < p_multimeshes.size() && capacity > 0) {
			RID rid = p_multimeshes[t];
			if (rid.is_valid()) {
				rs->multimesh_set_buffer(rid, type_buffers[t]);
			}
		}
	}
	return counts;
}

PackedFloat32Array HordeSim::get_type_buffer(int p_type, const Vector3 &p_target) {
	fill_type_buffers(p_target);
	if (p_type < 0 || p_type >= (int)type_buffers.size()) {
		return PackedFloat32Array();
	}
	return type_buffers[p_type];
}
