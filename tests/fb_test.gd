extends SceneTree

## 决定性实验：SubViewport 里的 hint_screen_texture 能不能读到上一帧？
## 着色器每帧往 R 通道加 0.125。若自反馈成立，N 帧后 R ≈ N*0.125；
## 若不成立（每帧被清空），R 恒为 0.125。
##
## godot --path . --script res://tests/fb_test.gd


const SHADER_CODE := """
shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D st : hint_screen_texture, filter_nearest;
void fragment() {
	COLOR = texture(st, UV) + vec4(0.125, 0.0, 0.0, 1.0);
}
"""


func _initialize() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(16, 16)
	vp.disable_3d = true
	vp.use_hdr_2d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	root.add_child(vp)

	var sh := Shader.new()
	sh.code = SHADER_CODE
	var m := ShaderMaterial.new()
	m.shader = sh

	var cr := ColorRect.new()
	cr.size = Vector2(16, 16)
	cr.material = m
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(cr)

	for i in 20:
		await process_frame

	var img := vp.get_texture().get_image()
	var px := img.get_pixel(8, 8)
	print("=== 自反馈测试 ===")
	print("格式 = %d（14=RGBH 浮点）" % img.get_format())
	print("20 帧后 R = %.4f" % px.r)
	print("预期：成立 ≈ 2.5（20 × 0.125）；不成立 ≈ 0.125")
	if px.r > 1.0:
		print("结论：自反馈成立 ✓")
	elif px.r > 0.2:
		print("结论：只读到最后一两帧 → 部分成立，需要另找缓冲方案 ✗")
	else:
		print("结论：自反馈不成立，每帧被清空 ✗")

	# 再测一次：显式清零一次后是否还能累积（排除 clear 模式没生效）
	print("\n[补充] clear_mode = %d（0=ALWAYS 1=NEVER 2=ONCE）" % vp.render_target_clear_mode)
	quit(0)
