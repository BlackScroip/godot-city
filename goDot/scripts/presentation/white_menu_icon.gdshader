shader_type canvas_item;

void fragment() {
    vec4 source = texture(TEXTURE, UV);
    float white = smoothstep(0.65, 0.95, min(source.r, min(source.g, source.b)));
    COLOR = vec4(COLOR.rgb, COLOR.a * source.a * white);
}
