using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace QuotaView.EffectsLab {
    // Windows ships the OpenGL 1.1 entry points; load shader/FBO functions from the active driver.
    // This surface is intentionally isolated from the WPF Island prototype.
    internal sealed class NativeGL : IDisposable {
        [StructLayout(LayoutKind.Sequential)] private struct PixelFormat {
            internal ushort Size, Version; internal uint Flags;
            internal byte Type, ColorBits, RedBits, RedShift, GreenBits, GreenShift, BlueBits, BlueShift, AlphaBits, AlphaShift;
            internal byte AccumBits, AccumRed, AccumGreen, AccumBlue, AccumAlpha, DepthBits, StencilBits, AuxBuffers, Layer, Reserved;
            internal uint LayerMask, VisibleMask, DamageMask;
        }
        [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hwnd);
        [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
        [DllImport("gdi32.dll")] private static extern int ChoosePixelFormat(IntPtr dc, ref PixelFormat format);
        [DllImport("gdi32.dll")] private static extern bool SetPixelFormat(IntPtr dc, int index, ref PixelFormat format);
        [DllImport("gdi32.dll")] private static extern bool SwapBuffers(IntPtr dc);
        [DllImport("opengl32.dll")] private static extern IntPtr wglCreateContext(IntPtr dc);
        [DllImport("opengl32.dll")] private static extern bool wglMakeCurrent(IntPtr dc, IntPtr context);
        [DllImport("opengl32.dll")] private static extern bool wglDeleteContext(IntPtr context);
        [DllImport("opengl32.dll", CharSet=CharSet.Ansi)] private static extern IntPtr wglGetProcAddress(string name);
        [DllImport("opengl32.dll")] private static extern IntPtr glGetString(uint name);
        [DllImport("opengl32.dll")] private static extern uint glGetError();
        [DllImport("opengl32.dll")] private static extern void glViewport(int x, int y, int w, int h);
        [DllImport("opengl32.dll")] private static extern void glClearColor(float r, float g, float b, float a);
        [DllImport("opengl32.dll")] private static extern void glClear(uint mask);
        [DllImport("opengl32.dll")] private static extern void glEnable(uint cap);
        [DllImport("opengl32.dll")] private static extern void glDisable(uint cap);
        [DllImport("opengl32.dll")] private static extern void glBlendFunc(uint src, uint dst);
        [DllImport("opengl32.dll")] private static extern void glBegin(uint mode);
        [DllImport("opengl32.dll")] private static extern void glEnd();
        [DllImport("opengl32.dll")] private static extern void glVertex2f(float x, float y);
        [DllImport("opengl32.dll")] private static extern void glTexCoord2f(float x, float y);
        [DllImport("opengl32.dll")] private static extern void glColor4f(float r, float g, float b, float a);
        [DllImport("opengl32.dll")] private static extern void glGenTextures(int n, out uint texture);
        [DllImport("opengl32.dll")] private static extern void glBindTexture(uint target, uint texture);
        [DllImport("opengl32.dll")] private static extern void glTexParameteri(uint target, uint name, int value);
        [DllImport("opengl32.dll")] private static extern void glTexImage2D(uint target, int level, int internalFormat, int w, int h, int border, uint format, uint type, IntPtr data);
        [DllImport("opengl32.dll")] private static extern void glDeleteTextures(int n, ref uint texture);
        [DllImport("opengl32.dll")] private static extern void glReadPixels(int x, int y, int w, int h, uint format, uint type, byte[] data);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate uint CreateShaderFn(uint type);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate void ShaderSourceFn(uint shader, int count, IntPtr sources, IntPtr lengths);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate void ObjectFn(uint handle);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate void GetIntFn(uint handle, uint name, out int value);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate void GetLogFn(uint handle, int size, out int length, StringBuilder log);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate uint CreateProgramFn();
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate void AttachFn(uint program, uint shader);
        [UnmanagedFunctionPointer(CallingConvention.Winapi, CharSet=CharSet.Ansi)] private delegate int UniformLocationFn(uint program, string name);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate void UniformFloatsFn(int location, int count, float[] data);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate void GenFn(int count, out uint id);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate void BindFn(uint target, uint id);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate void DeleteFn(int count, ref uint id);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate void AttachTextureFn(uint target, uint attachment, uint textarget, uint texture, int level);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate uint CheckFramebufferFn(uint target);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate int SwapIntervalFn(int interval);
        private CreateShaderFn createShader; private ShaderSourceFn shaderSource;
        private ObjectFn compileShader, deleteShader, linkProgram, useProgram, deleteProgram;
        private GetIntFn getShader, getProgram; private GetLogFn shaderLog, programLog;
        private CreateProgramFn createProgram; private AttachFn attachShader;
        private UniformLocationFn uniformLocation; private UniformFloatsFn uniformFloats;
        private GenFn genFramebuffer; private BindFn bindFramebuffer; private DeleteFn deleteFramebuffer;
        private AttachTextureFn attachTexture; private CheckFramebufferFn checkFramebuffer;
        private IntPtr window, dc, context;
        private uint orbProgram, quantumProgram, borderProgram;
        private sealed class OrbTarget { internal uint Buffer, Texture; internal int Size; }
        private readonly OrbTarget[] targets = { new OrbTarget(), new OrbTarget() };
        private int orbUniform, quantumUniform, borderUniform, surfaceHeight;
        internal string Device { get; private set; }
        internal bool Disposed { get; private set; }

        internal NativeGL(IntPtr hwnd, string shaderFolder) {
            window = hwnd;
            try {
                dc = GetDC(hwnd);
                var format = new PixelFormat { Size = (ushort)Marshal.SizeOf(typeof(PixelFormat)), Version=1,
                    Flags=0x00000004 | 0x00000020 | 0x00000001, Type=0, ColorBits=32, AlphaBits=8 };
                int index = ChoosePixelFormat(dc, ref format);
                if (index == 0 || !SetPixelFormat(dc, index, ref format)) throw new InvalidOperationException("无法创建 OpenGL 像素格式。");
                context = wglCreateContext(dc);
                if (context == IntPtr.Zero || !wglMakeCurrent(dc, context)) throw new InvalidOperationException("无法创建 OpenGL 上下文。");
                string version = Marshal.PtrToStringAnsi(glGetString(0x1F02));
                Device = Marshal.PtrToStringAnsi(glGetString(0x1F01)) + " · OpenGL " + version;
                if (version == null || version.StartsWith("1.") || version.StartsWith("2.") || version.StartsWith("3.0") || version.StartsWith("3.1") || version.StartsWith("3.2"))
                    throw new InvalidOperationException("需要 OpenGL 3.3+ 显卡驱动。当前：" + Device);
                createShader=Load<CreateShaderFn>("glCreateShader"); shaderSource=Load<ShaderSourceFn>("glShaderSource");
                compileShader=Load<ObjectFn>("glCompileShader"); deleteShader=Load<ObjectFn>("glDeleteShader");
                getShader=Load<GetIntFn>("glGetShaderiv"); shaderLog=Load<GetLogFn>("glGetShaderInfoLog");
                createProgram=Load<CreateProgramFn>("glCreateProgram"); attachShader=Load<AttachFn>("glAttachShader");
                linkProgram=Load<ObjectFn>("glLinkProgram"); useProgram=Load<ObjectFn>("glUseProgram"); deleteProgram=Load<ObjectFn>("glDeleteProgram");
                getProgram=Load<GetIntFn>("glGetProgramiv"); programLog=Load<GetLogFn>("glGetProgramInfoLog");
                uniformLocation=Load<UniformLocationFn>("glGetUniformLocation"); uniformFloats=Load<UniformFloatsFn>("glUniform1fv");
                genFramebuffer=Load<GenFn>("glGenFramebuffers"); bindFramebuffer=Load<BindFn>("glBindFramebuffer");
                deleteFramebuffer=Load<DeleteFn>("glDeleteFramebuffers"); attachTexture=Load<AttachTextureFn>("glFramebufferTexture2D");
                checkFramebuffer=Load<CheckFramebufferFn>("glCheckFramebufferStatus");
                // One window/context and a UI timer own pacing. Never block multiple preview draws on v-sync.
                IntPtr swap = wglGetProcAddress("wglSwapIntervalEXT");
                if (ValidProc(swap)) ((SwapIntervalFn)Marshal.GetDelegateForFunctionPointer(swap, typeof(SwapIntervalFn)))(0);
                string vertex=File.ReadAllText(Path.Combine(shaderFolder,"quad.vert"));
                orbProgram=Link(vertex, File.ReadAllText(Path.Combine(shaderFolder,"orb.frag")), "AI orb");
                quantumProgram=Link(vertex, File.ReadAllText(Path.Combine(shaderFolder,"quantum.frag")), "Quantum noise");
                borderProgram=Link(vertex, File.ReadAllText(Path.Combine(shaderFolder,"border.frag")), "Completion border");
                orbUniform=uniformLocation(orbProgram,"p[0]"); quantumUniform=uniformLocation(quantumProgram,"p[0]"); borderUniform=uniformLocation(borderProgram,"p[0]");
                if (orbUniform < 0 || quantumUniform < 0 || borderUniform < 0) throw new InvalidOperationException("Shader uniform binding failed.");
                glEnable(0x0BE2); glBlendFunc(0x0302,0x0303);
                foreach(var target in targets) genFramebuffer(1,out target.Buffer);
                CheckError("initialize");
            } catch { Dispose(); throw; }
        }
        private static bool ValidProc(IntPtr p) { return p != IntPtr.Zero && p.ToInt64() != 1 && p.ToInt64() != 2 && p.ToInt64() != 3 && p.ToInt64() != -1; }
        private static T Load<T>(string name) where T : class {
            IntPtr p=wglGetProcAddress(name);
            if (!ValidProc(p)) throw new InvalidOperationException("显卡驱动未提供 " + name);
            return Marshal.GetDelegateForFunctionPointer(p,typeof(T)) as T;
        }
        private uint Compile(uint type, string source, string label) {
            uint shader=createShader(type);
            IntPtr text=Marshal.StringToHGlobalAnsi(source), array=Marshal.AllocHGlobal(IntPtr.Size);
            try { Marshal.WriteIntPtr(array,text); shaderSource(shader,1,array,IntPtr.Zero); }
            finally { Marshal.FreeHGlobal(array); Marshal.FreeHGlobal(text); }
            compileShader(shader);
            int success; getShader(shader,0x8B81,out success);
            if (success == 0) {
                var log=new StringBuilder(16384); int count; shaderLog(shader,log.Capacity,out count,log); deleteShader(shader);
                throw new InvalidOperationException(label + " shader compile:\n" + log);
            }
            return shader;
        }
        private uint Link(string vertex, string fragment, string label) {
            uint v=0,f=0,p=0;
            try {
                v=Compile(0x8B31,vertex,label); f=Compile(0x8B30,fragment,label); p=createProgram();
                attachShader(p,v); attachShader(p,f); linkProgram(p);
                int ok; getProgram(p,0x8B82,out ok);
                if (ok == 0) { var log=new StringBuilder(16384); int count; programLog(p,log.Capacity,out count,log); throw new InvalidOperationException(label+" link:\n"+log); }
                return p;
            } catch { if (p != 0) deleteProgram(p); throw; }
            finally { if(v!=0)deleteShader(v); if(f!=0)deleteShader(f); }
        }
        internal void Begin(int width, int height) {
            if (!wglMakeCurrent(dc,context)) throw new InvalidOperationException("OpenGL context was lost.");
            surfaceHeight=height; bindFramebuffer(0x8D40,0); glViewport(0,0,width,height);
            glClearColor(.035f,.043f,.059f,1); glClear(0x4000);
        }
        private void View(Rectangle rect) { glViewport(rect.X,surfaceHeight-rect.Bottom,rect.Width,rect.Height); }
        private static void Quad(bool flip) {
            float top=flip?1:0, bottom=flip?0:1;
            glBegin(7);
            glTexCoord2f(0,bottom); glVertex2f(-1,-1); glTexCoord2f(1,bottom); glVertex2f(1,-1);
            glTexCoord2f(1,top); glVertex2f(1,1); glTexCoord2f(0,top); glVertex2f(-1,1);
            glEnd();
        }
        internal void Solid(Rectangle rect, Color color) {
            View(rect); useProgram(0); glDisable(0x0DE1);
            glColor4f(color.R/255f,color.G/255f,color.B/255f,color.A/255f); Quad(false); glColor4f(1,1,1,1);
        }
        private uint NewTexture(int width, int height, IntPtr data) {
            uint id; glGenTextures(1,out id); glBindTexture(0x0DE1,id);
            glTexParameteri(0x0DE1,0x2801,0x2601); glTexParameteri(0x0DE1,0x2800,0x2601);
            glTexParameteri(0x0DE1,0x2802,0x812F); glTexParameteri(0x0DE1,0x2803,0x812F);
            glTexImage2D(0x0DE1,0,0x8058,width,height,0,0x80E1,0x1401,data); glBindTexture(0x0DE1,0);
            return id;
        }
        internal uint Upload(Bitmap bitmap) {
            BitmapData bits=bitmap.LockBits(new Rectangle(0,0,bitmap.Width,bitmap.Height),ImageLockMode.ReadOnly,PixelFormatAlias);
            try { return NewTexture(bitmap.Width,bitmap.Height,bits.Scan0); } finally { bitmap.UnlockBits(bits); }
        }
        private static readonly System.Drawing.Imaging.PixelFormat PixelFormatAlias=System.Drawing.Imaging.PixelFormat.Format32bppArgb;
        internal void Texture(uint texture, Rectangle rect, bool flip) {
            View(rect); useProgram(0); glEnable(0x0DE1); glBindTexture(0x0DE1,texture); glColor4f(1,1,1,1); Quad(flip);
            glBindTexture(0x0DE1,0); glDisable(0x0DE1);
        }
        internal void DeleteTexture(ref uint texture) { if(texture!=0) { glDeleteTextures(1,ref texture); texture=0; } }
        internal void Orb(Rectangle rect, EffectsModel model, int slot) {
            OrbTarget target=targets[slot];
            int size=Math.Max(2,rect.Width*2);
            if (target.Size!=size) {
                DeleteTexture(ref target.Texture); target.Texture=NewTexture(size,size,IntPtr.Zero); target.Size=size;
                bindFramebuffer(0x8D40,target.Buffer); attachTexture(0x8D40,0x8CE0,0x0DE1,target.Texture,0);
                if(checkFramebuffer(0x8D40)!=0x8CD5) throw new InvalidOperationException("2x orb render target incomplete.");
            } else bindFramebuffer(0x8D40,target.Buffer);
            glViewport(0,0,size,size); glDisable(0x0BE2);
            useProgram(orbProgram); uniformFloats(orbUniform,128,model.OrbUniforms(size,size)); Quad(false);
            glEnable(0x0BE2); bindFramebuffer(0x8D40,0);
            Texture(target.Texture,rect,true);
        }
        internal void Quantum(Rectangle rect, EffectsModel model, float logicalScale) {
            View(rect); useProgram(quantumProgram);
            // Density is defined in source pixels. Keep it consistent in device-independent Windows units.
            float[] p=model.QuantumUniforms(Math.Max(1,(int)(rect.Width/logicalScale)),Math.Max(1,(int)(rect.Height/logicalScale)));
            uniformFloats(quantumUniform,p.Length,p); Quad(false);
        }
        internal void Border(Rectangle rect, EffectsModel model, float scale) {
            if (model.CompletionGlow <= 0) return;
            View(rect); useProgram(borderProgram);
            uniformFloats(borderUniform,4,new float[] {rect.Width,rect.Height,model.CompletionGlow,scale}); Quad(false);
        }
        internal void End() { useProgram(0); if(!SwapBuffers(dc))throw new InvalidOperationException("SwapBuffers failed."); }
        internal void CheckError(string step) {
            uint error=glGetError(); if(error!=0)throw new InvalidOperationException("OpenGL error 0x"+error.ToString("X")+" at "+step);
        }
        internal byte[] Read(Rectangle rect) {
            byte[] bytes=new byte[rect.Width*rect.Height*4];
            glReadPixels(rect.X,surfaceHeight-rect.Bottom,rect.Width,rect.Height,0x1908,0x1401,bytes);
            CheckError("shader pixel readback"); return bytes;
        }
        public void Dispose() {
            if (Disposed) return; Disposed=true;
            if (context!=IntPtr.Zero) {
                wglMakeCurrent(dc,context);
                if(deleteProgram!=null) { if(orbProgram!=0)deleteProgram(orbProgram); if(quantumProgram!=0)deleteProgram(quantumProgram); if(borderProgram!=0)deleteProgram(borderProgram); }
                foreach(var target in targets) {
                    DeleteTexture(ref target.Texture);
                    if(target.Buffer!=0 && deleteFramebuffer!=null)deleteFramebuffer(1,ref target.Buffer);
                }
                wglMakeCurrent(IntPtr.Zero,IntPtr.Zero); wglDeleteContext(context); context=IntPtr.Zero;
            }
            if(dc!=IntPtr.Zero){ReleaseDC(window,dc);dc=IntPtr.Zero;}
        }
    }
}
