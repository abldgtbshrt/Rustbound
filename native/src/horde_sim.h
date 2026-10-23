// Rustbound native horde simulation.
//
// HordeSim owns every enemy's state as flat arrays and runs the per-frame
// work that dominates frame time with a big horde: binning into a spatial
// grid, steering + separation + status effects, spatial queries, and writing
// the MultiMesh buffer.
//
// It never calls back into GDScript. Anything gameplay has to react to is
// queued instead and drained by EnemyManager after the call:
//   - get_contacts() / get_contact_dirs() + resolve_contacts(): enemies
//     touching the robot this step (the robot decides ram / crush / damage).
//   - take_kills(): enemies killed by bulk operations (burn in step(),
//     damage_radius()). damage() reports its kill through its return value.
//
// scripts/systems/horde_sim_gd.gd is the GDScript twin of this class with
// the exact same API and behavior. Keep them in sync; the parity tests in
// tests/run_tests.gd drive both and compare.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace godot {

class HordeSim : public RefCounted {
	GDCLASS(HordeSim, RefCounted)

public:
	HordeSim() = default;

	// --- Setup ---------------------------------------------------------------
	void setup(int p_capacity, float p_cell_size, float p_arena_half_extent);
	// One entry per enemy type. Cheap; EnemyManager calls it every step so
	// runtime edits to EnemyData (speed, color...) take effect immediately.
	// model_scale[t] > 0: the type has an authored mesh (faces -Z, origin at
	// its feet), drawn at that uniform scale. 0: the placeholder wedge.
	void set_types(const PackedFloat32Array &p_radius, const PackedFloat32Array &p_speed, const PackedColorArray &p_color, const PackedFloat32Array &p_model_scale);
	String backend_name() const { return "native"; }

	// --- Rows ----------------------------------------------------------------
	int get_count() const { return count; }
	int get_capacity() const { return capacity; }
	int spawn(int p_type, const Vector3 &p_at, float p_hp);
	void clear();
	void compact();

	bool is_alive(int i) const { return valid(i) && hp[i] > 0.0f; }
	int alive_count() const;

	Vector3 get_pos(int i) const { return valid(i) ? pos[i] : Vector3(); }
	void set_pos(int i, const Vector3 &p) { if (valid(i)) pos[i] = p; }
	Vector3 get_vel(int i) const { return valid(i) ? vel[i] : Vector3(); }
	void set_vel(int i, const Vector3 &v) { if (valid(i)) vel[i] = v; }
	float get_hp(int i) const { return valid(i) ? hp[i] : 0.0f; }
	void set_hp(int i, float v) { if (valid(i)) hp[i] = v; }
	int get_type(int i) const { return valid(i) ? type[i] : -1; }
	float get_flash(int i) const { return valid(i) ? flash[i] : 0.0f; }
	float get_cooldown(int i) const { return valid(i) ? cooldown[i] : 0.0f; }
	void set_cooldown(int i, float v) { if (valid(i)) cooldown[i] = v; }
	float get_slow_t(int i) const { return valid(i) ? slow_t[i] : 0.0f; }
	float get_slow_mult(int i) const { return valid(i) ? slow_mult[i] : 1.0f; }
	float get_burn_t(int i) const { return valid(i) ? burn_t[i] : 0.0f; }
	float get_burn_dps(int i) const { return valid(i) ? burn_dps[i] : 0.0f; }

	// --- Combat --------------------------------------------------------------
	bool damage(int i, float p_amount, const Vector3 &p_knockback);
	void apply_slow(int i, float p_mult, float p_duration);
	void apply_burn(int i, float p_dps, float p_duration);
	int damage_radius(const Vector3 &p_origin, float p_radius, float p_amount, float p_knockback);
	PackedInt32Array take_kills();

	// --- Queries -------------------------------------------------------------
	PackedInt32Array query_radius(const Vector3 &p_origin, float p_radius);
	PackedInt32Array query_segment(const Vector3 &p_origin, const Vector3 &p_dir, float p_reach, float p_width);
	int find_nearest(const Vector3 &p_origin, float p_max_range, const Vector3 &p_forward, float p_cos_half_arc);

	// --- Per frame -----------------------------------------------------------
	void rebuild_grid();
	void step(float p_delta, const Vector3 &p_target, float p_robot_radius, bool p_chase);
	PackedInt32Array get_contacts() const;
	PackedVector3Array get_contact_dirs() const;
	void resolve_contacts();
	// One MultiMesh per enemy type (each can have its own model). Fills and
	// uploads every type's buffer; returns how many instances each type has
	// (set each MultiMesh's visible_instance_count to it).
	PackedInt32Array upload_multimeshes(const Array &p_multimeshes, const Vector3 &p_target);
	// The buffer upload_multimeshes() would send for one type (tests).
	PackedFloat32Array get_type_buffer(int p_type, const Vector3 &p_target);

protected:
	static void _bind_methods();

private:
	bool valid(int i) const { return i >= 0 && i < count; }
	int cell_x(float x) const;
	int cell_z(float z) const;
	void ensure_grid() {
		if (grid_dirty) {
			rebuild_grid();
		}
	}
	float type_radius(int t) const { return (t >= 0 && t < (int)t_radius.size()) ? t_radius[t] : 0.5f; }

	int capacity = 0;
	int count = 0;
	float cell_size = 2.0f;
	float arena_half = 58.0f;

	std::vector<Vector3> pos, vel;
	std::vector<float> hp, flash, cooldown, slow_t, slow_mult, burn_t, burn_dps;
	std::vector<int> type;

	std::vector<float> t_radius, t_speed;
	std::vector<Color> t_color;
	std::vector<Basis> t_shape; // tip + scale applied after the look-at basis
	std::vector<float> t_lift; // origin offset along Y (authored models sit on their feet)
	float max_radius = 0.5f;

	// Spatial grid (counting sort). Cells cover the arena plus one cell.
	int grid_min = 0; // lowest cell coordinate on both axes
	int grid_n = 0; // cells per axis
	std::vector<int> cell_start; // grid_n * grid_n + 1
	std::vector<int> cell_items; // enemy indices sorted by cell
	std::vector<int> cell_of; // scratch: cell per enemy
	std::vector<int> cell_fill; // scratch: write cursor per cell
	bool grid_dirty = true;

	std::vector<int> contacts;
	std::vector<Vector3> contact_dirs, contact_push;
	std::vector<int> kills;
	std::vector<PackedFloat32Array> type_buffers;
	std::vector<int> type_counts;
	void fill_type_buffers(const Vector3 &p_target);
};

} // namespace godot
