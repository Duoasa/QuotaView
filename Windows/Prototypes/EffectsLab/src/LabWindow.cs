using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace QuotaView.EffectsLab {
    internal static class LabLog {
        internal static readonly string Folder=Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"..",".local"));
        internal static void Write(string file, string text) {
            try { Directory.CreateDirectory(Folder); File.WriteAllText(Path.Combine(Folder,file),text); } catch(IOException) {} catch(UnauthorizedAccessException) {}
        }
    }

    internal sealed class EffectsCanvas : Control {
        private NativeGL gl;
        internal readonly EffectsModel Model;
        private uint overlay;
        private bool dirty=true, checkedPipeline;
        internal string Error { get; private set; }
        internal string Device { get { return gl==null ? "GPU 初始化中" : gl.Device; } }
        internal long Frames { get; private set; }
        internal string PipelineResult { get; private set; }
        private Rectangle orbPanel, quantumPanel, bigOrb, bigQuantum, card, smallOrb;
        private float scale=1;
        internal EffectsCanvas(EffectsModel model) {
            Model=model; Dock=DockStyle.Fill; BackColor=Color.FromArgb(9,11,15);
            SetStyle(ControlStyles.Opaque | ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint,true);
        }
        protected override CreateParams CreateParams { get { var p=base.CreateParams; p.ClassStyle |= 0x20; return p; } }
        internal void RefreshLabels() { dirty=true; Invalidate(); }
        protected override void OnResize(EventArgs e) { base.OnResize(e); dirty=true; Invalidate(); }
        protected override void OnPaintBackground(PaintEventArgs e) {}
        protected override void OnPaint(PaintEventArgs e) {
            if(Error!=null) { PaintError(e.Graphics); return; }
            try { Render(); }
            catch(Exception ex) { Error=ex.ToString(); LabLog.Write("error.txt",Error); PaintError(e.Graphics); }
        }
        private void PaintError(Graphics g) {
            g.Clear(BackColor);
            using(var font=new Font("Microsoft YaHei UI",11))
            using(var brush=new SolidBrush(Color.FromArgb(255,174,174)))
                g.DrawString("特效渲染未启动\n\n"+Error,font,brush,new RectangleF(30,25,Math.Max(100,Width-60),Math.Max(100,Height-50)));
        }
        private Rectangle R(float x,float y,float w,float h) { return new Rectangle((int)Math.Round(x*scale),(int)Math.Round(y*scale),Math.Max(1,(int)Math.Round(w*scale)),Math.Max(1,(int)Math.Round(h*scale))); }
        private void LayoutScene() {
            using(var g=CreateGraphics()) scale=g.DpiX/96f;
            float w=Width/scale,h=Height/scale, top=Math.Max(160,Math.Min(304,h-154));
            float left=Math.Min(300,w*.31f), orbSize=Math.Min(268,top-46);
            orbPanel=R(16,12,left,top); quantumPanel=R(left+32,12,w-left-48,top);
            bigOrb=R(16+(left-orbSize)/2,44+(top-40-orbSize)/2,orbSize,orbSize);
            bigQuantum=R(left+54,Math.Max(74,top*.34f),w-left-92,Math.Max(68,Math.Min(136,top-112)));
            float cardWidth=Math.Min(624,w-96), cardY=top+65;
            card=R((w-cardWidth)/2,cardY,cardWidth,68);
            // 24 DIP sphere, same 0.535 geometry and 2x supersampling as the large preview.
            float canvasSize=24f/.535f;
            smallOrb=R((w-cardWidth)/2+8,cardY+(68-canvasSize)/2,canvasSize,canvasSize);
        }
        private void Label(Graphics g,string text,float x,float y,float size,Color color,bool bold) {
            using(var font=new Font("Microsoft YaHei UI",size*scale, bold?FontStyle.Bold:FontStyle.Regular,GraphicsUnit.Pixel))
            using(var brush=new SolidBrush(color)) g.DrawString(text,font,brush,x*scale,y*scale);
        }
        private void RebuildOverlay() {
            if(overlay!=0)gl.DeleteTexture(ref overlay);
            using(var bitmap=new Bitmap(Width,Height,System.Drawing.Imaging.PixelFormat.Format32bppArgb))
            using(var g=Graphics.FromImage(bitmap)) {
                g.Clear(Color.Transparent); g.SmoothingMode=SmoothingMode.AntiAlias; g.TextRenderingHint=TextRenderingHint.AntiAliasGridFit;
                Color text=Color.FromArgb(229,233,240),muted=Color.FromArgb(121,133,154);
                using(var pen=new Pen(Color.FromArgb(42,48,63),scale)) {
                    g.DrawRectangle(pen,orbPanel); g.DrawRectangle(pen,quantumPanel);
                }
                Label(g,"01   AI 球",orbPanel.X/scale+18,orbPanel.Y/scale+14,15,text,true);
                Label(g,"RIPPLE GLOW",orbPanel.X/scale+18,orbPanel.Bottom/scale-29,10,muted,false);
                Label(g,"02   量子噪点进度条",quantumPanel.X/scale+20,quantumPanel.Y/scale+14,15,text,true);
                Label(g,"QUANTUM NOISE",quantumPanel.X/scale+20,quantumPanel.Bottom/scale-29,10,muted,false);
                Label(g,"组合预览  /  24 DIP 球体 · 68 DIP 卡片",card.X/scale,card.Y/scale-31,12,muted,false);
                Label(g,"QuotaView Windows",card.X/scale+61,card.Y/scale+12,13,text,true);
                Label(g,EffectsModel.Names[(int)Model.State]+"  ·  本地模拟",card.X/scale+61,card.Y/scale+35,11,Color.FromArgb(189,198,213),false);
                string progress=Model.State==EffectState.Completed?"100%":Math.Round(Model.Progress*100)+"%";
                Label(g,progress,card.Right/scale-66,card.Y/scale+23,17,text,true);
                overlay=gl.Upload(bitmap);
            }
            dirty=false;
        }
        private void Render() {
            if(Width<10 || Height<10 || !IsHandleCreated)return;
            if(gl==null)gl=new NativeGL(Handle,Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"shaders"));
            gl.Begin(Width,Height);
            if(!checkedPipeline) { PipelineResult=RunPipelineChecks(); checkedPipeline=true; LabLog.Write("gpu-smoke.txt",Device+Environment.NewLine+PipelineResult); gl.Begin(Width,Height); }
            if(dirty){LayoutScene();RebuildOverlay();}
            gl.Solid(orbPanel,Color.Black); gl.Solid(quantumPanel,Color.Black);
            gl.Orb(bigOrb,Model,0); gl.Quantum(bigQuantum,Model,scale); gl.Border(bigQuantum,Model,scale);
            gl.Quantum(card,Model,scale); gl.Orb(smallOrb,Model,1); gl.Border(card,Model,scale);
            gl.Texture(overlay,new Rectangle(0,0,Width,Height),false);
            if(Frames%120==0)gl.CheckError("frame");
            gl.End(); Frames++;
        }
        // GPU readbacks test shader execution and temporal response, never UI appearance.
        // Nothing is captured to an image; no control interaction or screenshot acceptance occurs here.
        private string RunPipelineChecks() {
            Rectangle area=new Rectangle(0,0,160,96), sphere=new Rectangle(0,0,96,96);
            var fixture=new EffectsModel();
            gl.Solid(area,Color.Black); gl.Orb(sphere,fixture,1); byte[] a=gl.Read(sphere);
            if(PixelEnergy(a)<5000)throw new InvalidOperationException("AI orb shader produced no usable signal.");
            for(int i=0;i<60;i++)fixture.Advance(1.0/60);
            gl.Solid(area,Color.Black); gl.Orb(sphere,fixture,1); byte[] b=gl.Read(sphere);
            if(Difference(a,b)<1000)throw new InvalidOperationException("AI orb shader did not respond to time.");
            fixture.SetReducedMotion(true); fixture.SetProgress(0);
            gl.Solid(area,Color.Black); gl.Quantum(area,fixture,1); a=gl.Read(area);
            fixture.SetProgress(.95); gl.Solid(area,Color.Black); gl.Quantum(area,fixture,1); b=gl.Read(area);
            if(Difference(a,b)<1000)throw new InvalidOperationException("Quantum shader did not respond to progress.");
            fixture.SetState(EffectState.Completed); gl.Solid(area,Color.Black); gl.Quantum(area,fixture,1); a=gl.Read(area);
            if(PixelEnergy(a)>100)throw new InvalidOperationException("Reduced-motion completion did not settle.");
            gl.CheckError("GPU checks");
            return "PASS: orb signal; orb time response; quantum progress response; reduced-motion completion; GL errors=0.\nThese are shader pipeline checks, not visual acceptance.";
        }
        private static long PixelEnergy(byte[] pixels) { long n=0; for(int i=0;i<pixels.Length;i+=4)n+=pixels[i]+pixels[i+1]+pixels[i+2]; return n; }
        private static long Difference(byte[] a,byte[] b) { long n=0; for(int i=0;i<a.Length;i+=4)for(int k=0;k<3;k++)n+=Math.Abs(a[i+k]-b[i+k]); return n; }
        protected override void OnHandleDestroyed(EventArgs e) {
            if(gl!=null) { if(overlay!=0)gl.DeleteTexture(ref overlay); gl.Dispose(); gl=null; }
            checkedPipeline=false; dirty=true; base.OnHandleDestroyed(e);
        }
    }

    internal sealed class LabWindow : Form {
        [DllImport("winmm.dll")] private static extern uint timeBeginPeriod(uint milliseconds);
        [DllImport("winmm.dll")] private static extern uint timeEndPeriod(uint milliseconds);
        private bool highResolutionClock;
        private readonly EffectsModel model=new EffectsModel();
        private readonly EffectsCanvas canvas;
        private readonly Timer timer=new Timer {Interval=16};
        private readonly Stopwatch clock=Stopwatch.StartNew();
        private double last,lastReport;
        private long lastFrames;
        private readonly Label status=new Label(),progressLabel=new Label(),description=new Label();
        private readonly TrackBar progress=new TrackBar();
        private readonly Button pause=new Button();
        private readonly Button[] stateButtons=new Button[9];
        private readonly CheckBox reduced=new CheckBox();
        private readonly bool smokeOnly;
        private bool ready;
        internal LabWindow(bool smoke) {
            smokeOnly=smoke;
            Text="QuotaView · 特效开发台"; BackColor=Color.FromArgb(15,18,25); ForeColor=Color.FromArgb(224,230,241);
            Font=new Font("Microsoft YaHei UI",9); AutoScaleDimensions=new SizeF(96,96); AutoScaleMode=AutoScaleMode.Dpi;
            ClientSize=new Size(1120,740); MinimumSize=new Size(1000,580); StartPosition=FormStartPosition.CenterScreen;
            var layout=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=1,RowCount=4,Padding=new Padding(20,14,20,6)};
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute,62)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute,146));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent,100)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute,29));
            var header=new Panel {Dock=DockStyle.Fill};
            header.Controls.Add(new Label {Text="特效开发台",AutoSize=true,Font=new Font(Font.FontFamily,20,FontStyle.Bold),Location=new Point(0,0)});
            header.Controls.Add(new Label {Text="AI 球  /  量子噪点  ·  v0.7.7-build.1",AutoSize=true,ForeColor=Color.FromArgb(138,151,175),Location=new Point(2,39)});
            var badge=new Label {Text="DEBUG  ·  模拟数据",AutoSize=true,ForeColor=Color.FromArgb(136,194,255),Anchor=AnchorStyles.Top|AnchorStyles.Right};
            header.Controls.Add(badge); header.Resize+=delegate {badge.Location=new Point(header.Width-badge.PreferredWidth-4,12);};
            layout.Controls.Add(header,0,0);
            var controls=new TableLayoutPanel {Dock=DockStyle.Fill,RowCount=3,ColumnCount=1,Margin=Padding.Empty};
            controls.RowStyles.Add(new RowStyle(SizeType.Absolute,45)); controls.RowStyles.Add(new RowStyle(SizeType.Absolute,29)); controls.RowStyles.Add(new RowStyle(SizeType.Absolute,66));
            var states=new FlowLayoutPanel {Dock=DockStyle.Fill,WrapContents=false,AutoScroll=true,Margin=Padding.Empty};
            for(int i=0;i<stateButtons.Length;i++) {
                int selected=i; var b=MakeButton(EffectsModel.Names[i],i==2?106:78); stateButtons[i]=b;
                b.Click+=delegate {model.SetState((EffectState)selected); UpdateControls();}; states.Controls.Add(b);
            }
            controls.Controls.Add(states,0,0);
            description.Dock=DockStyle.Fill; description.ForeColor=Color.FromArgb(148,161,184); description.Padding=new Padding(2,3,0,0); controls.Controls.Add(description,0,1);
            var row=new FlowLayoutPanel {Dock=DockStyle.Fill,WrapContents=false,AutoScroll=true,Margin=Padding.Empty};
            progressLabel.Width=92; progressLabel.Height=32; progressLabel.TextAlign=ContentAlignment.MiddleLeft;
            progress.Minimum=0; progress.Maximum=95; progress.Value=60; progress.Width=194; progress.Height=37; progress.TickStyle=TickStyle.None; progress.SmallChange=1; progress.LargeChange=10;
            progress.AccessibleName="模拟进度，0 到 95 百分比";
            progress.ValueChanged+=delegate {model.SetProgress(progress.Value/100.0);UpdateControls();};
            row.Controls.Add(progressLabel); row.Controls.Add(progress);
            foreach(int v in new int[]{0,1,50,95}) { int n=v; var b=MakeButton(v+"%",45); b.Click+=delegate { if(model.State==EffectState.Completed)model.SetState(EffectState.Working); progress.Value=n;UpdateControls();}; row.Controls.Add(b); }
            var complete=MakeButton("完成 / 重播",100); complete.Click+=delegate {model.Paused=false;model.ReplayCompletion();UpdateControls();}; row.Controls.Add(complete);
            StyleButton(pause,67); pause.Click+=delegate {model.Paused=!model.Paused;UpdateControls();}; row.Controls.Add(pause);
            var reset=MakeButton("重置",62);reset.Click+=delegate {model.Restart();canvas.RefreshLabels();};row.Controls.Add(reset);
            var speed=new ComboBox {DropDownStyle=ComboBoxStyle.DropDownList,Width=68,Margin=new Padding(8,5,6,0),AccessibleName="播放速度"};
            speed.Items.AddRange(new object[]{"0.5×","1×","1.5×","2×"});speed.SelectedIndex=1;
            speed.SelectedIndexChanged+=delegate {model.Speed=new double[]{.5,1,1.5,2}[speed.SelectedIndex];}; row.Controls.Add(speed);
            reduced.Text="减少动态效果";reduced.AutoSize=true;reduced.Margin=new Padding(6,8,0,0);reduced.CheckedChanged+=delegate {model.SetReducedMotion(reduced.Checked);UpdateControls();};row.Controls.Add(reduced);
            controls.Controls.Add(row,0,2);layout.Controls.Add(controls,0,1);
            canvas=new EffectsCanvas(model);layout.Controls.Add(canvas,0,2);
            status.Dock=DockStyle.Fill;status.TextAlign=ContentAlignment.MiddleLeft;status.ForeColor=Color.FromArgb(119,134,157);status.Font=new Font("Segoe UI",8);layout.Controls.Add(status,0,3);
            Controls.Add(layout);UpdateControls();
            timer.Tick+=OnTick;
            Shown+=delegate {
                Rectangle area=Screen.FromControl(this).WorkingArea;
                MinimumSize=new Size(Math.Min(MinimumSize.Width,area.Width-48),Math.Min(MinimumSize.Height,area.Height-48));
                Size=new Size(Math.Min(Width,area.Width-48),Math.Min(Height,area.Height-48));
                Location=new Point(area.Left+(area.Width-Width)/2,area.Top+(area.Height-Height)/2);
                ready=true;last=clock.Elapsed.TotalSeconds;SetClockResolution();timer.Start();
            };
            Resize+=delegate { if(ready){last=clock.Elapsed.TotalSeconds;SetClockResolution();if(WindowState==FormWindowState.Minimized)timer.Stop();else{timer.Start();canvas.Invalidate();}} };
            FormClosed+=delegate {timer.Stop();timer.Dispose();if(highResolutionClock){timeEndPeriod(1);highResolutionClock=false;}LabLog.Write("status.txt","closed\n"+DateTimeOffset.Now.ToString("o"));};
        }
        private Button MakeButton(string text,int width) {var b=new Button {Text=text};StyleButton(b,width);return b;}
        private void StyleButton(Button b,int width) {b.Width=width;b.Height=33;b.FlatStyle=FlatStyle.Flat;b.FlatAppearance.BorderColor=Color.FromArgb(52,62,79);b.BackColor=Color.FromArgb(26,33,46);b.ForeColor=ForeColor;b.Margin=new Padding(0,0,6,0);b.Cursor=Cursors.Hand;b.UseVisualStyleBackColor=false;}
        private void UpdateControls() {
            for(int i=0;i<9;i++) {stateButtons[i].BackColor=(int)model.State==i?Color.FromArgb(54,80,121):Color.FromArgb(26,33,46);stateButtons[i].FlatAppearance.BorderColor=(int)model.State==i?Color.FromArgb(112,160,233):Color.FromArgb(52,62,79);}
            description.Text=EffectsModel.Descriptions[(int)model.State]+"  ·  切换状态不会重置运动相位";
            progress.Enabled=model.State!=EffectState.Completed;
            progressLabel.Text=model.State==EffectState.Completed?"进度  100%":"进度  "+progress.Value+"%";
            pause.Text=model.Paused?"继续":"暂停";
            if(ready)SetClockResolution();
            if(canvas!=null)canvas.RefreshLabels();
        }
        private void SetClockResolution() {
            bool needed=WindowState!=FormWindowState.Minimized && !model.Paused && !model.ReduceMotion;
            if(needed && !highResolutionClock) highResolutionClock=timeBeginPeriod(1)==0;
            else if(!needed && highResolutionClock) {timeEndPeriod(1);highResolutionClock=false;}
        }
        private void OnTick(object sender,EventArgs e) {
            double now=clock.Elapsed.TotalSeconds,dt=now-last;last=now;
            model.Advance(dt);
            if((!model.Paused && !model.ReduceMotion)||canvas.Frames==0)canvas.Invalidate();
            if(canvas.Error!=null) {timer.Stop();if(highResolutionClock){timeEndPeriod(1);highResolutionClock=false;}status.Text="渲染失败 · 详情见开发台及 .local/error.txt";if(smokeOnly){Environment.ExitCode=1;Close();}return;}
            if(smokeOnly && canvas.Frames>=3) {Environment.ExitCode=0;Close();return;}
            if(now-lastReport>=2) {
                double fps=(canvas.Frames-lastFrames)/(now-lastReport);lastReport=now;lastFrames=canvas.Frames;
                string mode=model.ReduceMotion?"Reduced motion":model.Paused?"Paused":fps.ToString("F0")+" fps";
                status.Text=mode+"   ·   "+canvas.Device;
                LabLog.Write("status.txt",DateTimeOffset.Now.ToString("o")+"\nframes="+canvas.Frames+"\n"+mode+"\n"+canvas.Device+"\nstate="+model.State+"\n"+canvas.PipelineResult);
            }
        }
    }
}
