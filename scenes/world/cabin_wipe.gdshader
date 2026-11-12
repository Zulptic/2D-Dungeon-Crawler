shader_type canvas_item;
render_mode unshaded;

uniform float progress = 0.0;
uniform bool covering = true;

void fragment() {
	float angled_x = UV.x + (UV.y - 0.5) * 0.36;
	float edge = mix(-0.19, 1.19, progress);
	float covered = step(angled_x, edge);
	COLOR = vec4(0.0, 0.0, 0.0, covering ? covered : 1.0 - covered);
}
