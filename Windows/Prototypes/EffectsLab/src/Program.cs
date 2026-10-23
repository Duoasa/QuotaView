using System;
using System.Windows.Forms;
namespace QuotaView.EffectsLab {
    internal static class Program {
        [STAThread] private static void Main(string[] args) {
            Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);
            try { using(var window=new LabWindow(Array.IndexOf(args,"--smoke")>=0)) Application.Run(window); }
            catch(Exception ex) {LabLog.Write("error.txt",ex.ToString());Environment.ExitCode=1;MessageBox.Show(ex.Message,"QuotaView 特效开发台",MessageBoxButtons.OK,MessageBoxIcon.Error);}
        }
    }
}
