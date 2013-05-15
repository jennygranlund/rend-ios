
precision mediump float;

uniform sampler2D s_textureY;
uniform sampler2D s_textureUV;

uniform mat3 u_colorConversionMatrix;
uniform float u_exposure;

varying vec2 v_texCoord;
varying vec2 v_position;

void main() {
    mediump vec3 yuv;
	lowp vec3 rgb;
	
	// Subtract constants to map the video range start at 0
	yuv.x = (texture2D(s_textureY, v_texCoord).r - (16.0/255.0))* 1.0;
	yuv.yz = (texture2D(s_textureUV, v_texCoord).rg - vec2(0.5, 0.5))* 1.0;
	
	rgb = u_colorConversionMatrix * yuv;
    
	gl_FragColor = vec4(rgb, 1.0);
}
