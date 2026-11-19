extends RefCounted
## Procedural wood: stretched fractal noise plus bent growth rings, blended between two tones.

static func make(light: Color, dark: Color, rng_seed: int, rough: float = 0.42, uv_scale: float = 0.6, ring_count: int = 6) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.03
	noise.seed = rng_seed
	var res := 256
	# Narrow in one axis, then stretched: features run long in y, like grain.
	var base := noise.get_seamless_image(res, 40, false, false, 0.2, true)
	base.resize(res, res, Image.INTERPOLATE_BILINEAR)
	var img := Image.create(res, res, false, Image.FORMAT_RGB8)
	for y in res:
		for x in res:
			var f := base.get_pixel(x, y).r
			var ring := 0.5 + 0.5 * sin(float(x) / res * TAU * ring_count + f * 9.0)
			var v := clampf(0.55 * f + 0.45 * ring, 0.0, 1.0)
			img.set_pixel(x, y, dark.lerp(light, v))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = rough
	m.clearcoat_enabled = true
	m.clearcoat = 0.35
	m.clearcoat_roughness = 0.25
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
