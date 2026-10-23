using System;
using QuotaView.EffectsLab;

internal static class ModelTests {
    private static int count;
    private static void Check(bool condition,string message) {count++;if(!condition)throw new Exception(message);}
    private static bool Near(double a,double b,double tolerance) {return Math.Abs(a-b)<=tolerance;}
    private static void Advance(EffectsModel m,double seconds,int fps) {for(int i=0;i<(int)Math.Round(seconds*fps);i++)m.Advance(1.0/fps);}
    private static void Same(float[] a,float[] b,string message) {bool same=a.Length==b.Length;for(int i=0;i<a.Length && same;i++)same=a[i]==b[i];Check(same,message);}
    private static void Main() {
        var m=new EffectsModel();
        m.SetProgress(1);Check(m.Progress==.95,"Non-completed progress must cap at 95%.");
        Advance(m,15,60);Check(m.Front<=.95 && m.State==EffectState.Working,"Time must not create a completion event.");
        m.SetProgress(double.NaN);Check(m.Progress==.95,"Ignore invalid progress.");
        float[] before=m.OrbUniforms(256,256);double phase=m.OrbPhase,displacement=m.Displacement;
        m.SetState(EffectState.Thinking);
        Same(before,m.OrbUniforms(256,256),"State switch must start from the current sphere.");
        Check(phase==m.OrbPhase && displacement==m.Displacement,"State change must preserve integrated motion.");
        Advance(m,.15,60);before=m.OrbUniforms(256,256);
        m.SetState(EffectState.Error);Same(before,m.OrbUniforms(256,256),"Interrupted transition must not restart from a preset.");
        float[] q=m.QuantumUniforms(624,68);before=m.OrbUniforms(256,256);
        m.Paused=true;Advance(m,5,60);Same(q,m.QuantumUniforms(624,68),"Pause must stop the field.");Same(before,m.OrbUniforms(256,256),"Pause must stop the sphere.");
        m.Paused=false;m.SetReducedMotion(true);m.SetState(EffectState.Waiting);
        before=m.OrbUniforms(256,256);q=m.QuantumUniforms(624,68);Advance(m,5,60);
        Same(before,m.OrbUniforms(256,256),"Reduced motion must freeze sphere time.");Same(q,m.QuantumUniforms(624,68),"Reduced motion must freeze field time.");
        m.SetState(EffectState.Completed);q=m.QuantumUniforms(624,68);
        Check(q[13]==1 && q[14]==0 && q[16]==0 && m.CompletionGlow>0,"Reduced completion must settle immediately.");
        m.SetReducedMotion(false);Check(m.QuantumUniforms(624,68)[16]==0,"Re-enabling motion must not replay a completed burst.");
        m=new EffectsModel();m.SetProgress(.95);Advance(m,3,60);m.ReplayCompletion();
        q=m.QuantumUniforms(624,68);Check(q[13]==0 && q[16]==1,"Completion must begin at the existing front.");
        Advance(m,.5,60);q=m.QuantumUniforms(624,68);Check(q[13]==1 && q[14]>0 && q[14]<=.18f,"Completion must fill, then briefly highlight.");
        Advance(m,1,60);q=m.QuantumUniforms(624,68);Check(q[16]==0 && m.CompletionGlow>0,"Completion must fade and reveal border.");
        Advance(m,5,60);Check(m.QuantumUniforms(624,68)[16]==0,"Completion must not loop the particle burst.");
        m.ReplayCompletion();Check(m.CompletionTime==0 && m.QuantumUniforms(624,68)[16]==1,"Replay must explicitly rearm the one-shot.");
        m.SetState(EffectState.Working);Check(m.QuantumUniforms(624,68)[17]==0,"Returning to work clears completion.");
        var low=new EffectsModel();var high=new EffectsModel();
        low.SetState(EffectState.Compacting);high.SetState(EffectState.Compacting);
        Advance(low,2,30);Advance(high,2,120);
        Check(Near(low.Displacement,high.Displacement,.001),"Motion integration must be frame-rate independent.");
        Check(Near(low.QuantumPhase,high.QuantumPhase,.001),"Quantum clock must be frame-rate independent.");
        Check(Near(low.OrbPhase,high.OrbPhase,.001),"Sphere phase must be frame-rate independent.");
        m=new EffectsModel();Advance(m,900,60);
        Check(m.QuantumPhase>=0 && m.QuantumPhase<256,"Bound the shader clock for long sessions.");
        Check(Math.Abs(m.Displacement)<EffectsModel.LatticePeriod,"Wrap displacement at the exact particle lattice period.");
        foreach(EffectState state in Enum.GetValues(typeof(EffectState))) {
            m.SetReducedMotion(true);m.SetState(state);float[] o=m.OrbUniforms(256,256);q=m.QuantumUniforms(624,68);
            bool valid=true;foreach(float f in o)valid &= !float.IsNaN(f) && !float.IsInfinity(f);foreach(float f in q)valid &= !float.IsNaN(f) && !float.IsInfinity(f);
            Check(valid,"All state uniforms must remain finite: "+state);
            Check(o[4]==.535f && o[15]==9 && o[19]==1 && o[21]==0,"All states preserve the release sphere silhouette: "+state);
        }
        m=new EffectsModel();phase=m.OrbPhase;m.Advance(double.NaN);m.Advance(-1);Check(m.OrbPhase==phase,"Invalid deltas must not corrupt animation.");
        Console.WriteLine("PASS: "+count+" model checks (continuity, interruption, progress, completion, pause, reduced motion, frame rates, long sessions).");
    }
}
