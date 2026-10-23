#version 330 compatibility
// Windows host completion outline; timing comes from the release completion contract.
uniform float p[4];
in vec2 uv;
out vec4 fragColor;
void main() {
    vec2 size=vec2(p[0],p[1]);
    float scale=p[3];
    vec2 halfSize=size*.5;
    vec2 q=abs(uv*size-halfSize)-halfSize+12.0*scale;
    float d=length(max(q,vec2(0)))+min(max(q.x,q.y),0.0)-10.0*scale;
    float line=(1.0-smoothstep(.5*scale,1.6*scale,abs(d)))*.8;
    float glow=exp(-abs(d)/(3.0*scale))*.22;
    fragColor=vec4(.28,.93,.62,(line+glow)*p[2]);
}
