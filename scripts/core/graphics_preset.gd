class_name GraphicsPreset
extends Resource
## Data-only description of one graphics quality level (Low / Medium / High / Ultra).
##
## Presets live in res://resources/settings/graphics_presets/ and are applied by
## SettingsManager. Tweak the .tres files in the inspector — no code changes needed.

enum Quality { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }

@export var quality: Quality = Quality.MEDIUM
@export var display_name: String = "Medium"

@export_group("Renderer")
## "gl_compatibility" (OpenGL 3.3, fastest on weak/integrated GPUs) or "forward_plus" (Vulkan).
## Changing the renderer requires a restart.
@export_enum("gl_compatibility", "forward_plus") var rendering_method: String = "forward_plus"

@export_group("Resolution")
## 3D render resolution relative to the window (UI always renders at full resolution).
@export_range(0.5, 1.0, 0.05) var render_scale: float = 1.0
@export var scaling_mode: Viewport.Scaling3DMode = Viewport.SCALING_3D_MODE_BILINEAR
## Only used by FSR 1.0 / FSR 2.2.
@export_range(0.0, 2.0, 0.05) var fsr_sharpness: float = 0.2

@export_group("Anti-aliasing")
@export var msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
@export var fxaa: bool = false
@export var taa: bool = false

@export_group("Textures & Detail")
## Positive values force lower-resolution mipmaps (saves VRAM and bandwidth).
@export_range(-1.0, 2.0, 0.25) var texture_mipmap_bias: float = 0.0
## Higher = more aggressive mesh LOD switching (cheaper).
@export_range(0.5, 8.0, 0.5) var mesh_lod_threshold: float = 1.0
## Multipliers read by gameplay/level scripts.
@export_range(0.25, 1.5, 0.05) var draw_distance_scale: float = 1.0
@export_range(0.0, 1.0, 0.05) var foliage_density: float = 1.0
@export_range(0.0, 1.0, 0.05) var particle_amount: float = 1.0
## Procedural surface detail (noise, wood grain, stone tiles) in the level shader.
@export var surface_detail: bool = true

@export_group("Shadows")
@export var shadows_enabled: bool = true
@export_enum("512:512", "1024:1024", "2048:2048", "4096:4096", "8192:8192") var directional_shadow_size: int = 2048
@export_enum("0:0", "1024:1024", "2048:2048", "4096:4096", "8192:8192") var positional_shadow_atlas_size: int = 2048
@export var shadow_filter_quality: RenderingServer.ShadowQuality = RenderingServer.SHADOW_QUALITY_SOFT_LOW
@export_range(1, 4) var directional_shadow_cascades: int = 2

@export_group("Lights")
## Decorative point/spot lights in levels (lamps, muzzle flashes). In the
## Compatibility renderer every light costs an extra pass per lit object.
@export var dynamic_lights: bool = true

@export_group("Effects (Environment)")
@export var ssao: bool = false
@export var ssil: bool = false
@export var ssr: bool = false
@export var sdfgi: bool = false
@export var glow: bool = true
@export var volumetric_fog: bool = false
@export var depth_of_field: bool = false
