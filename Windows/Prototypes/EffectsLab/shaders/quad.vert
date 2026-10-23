#version 330 compatibility
out vec2 uv;
void main() {
    gl_Position = gl_Vertex;
    uv = vec2(gl_MultiTexCoord0.x, gl_MultiTexCoord0.y);
}
