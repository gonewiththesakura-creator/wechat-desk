using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class WeChatDeskLauncher
{
    [STAThread]
    private static void Main()
    {
        string root = @"D:\WeChatDesk";
        bool installed = File.Exists(Path.Combine(root, "desktop-installed.txt"));
        string script = Path.Combine(root, "setup", installed ? "open.ps1" : "setup.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("找不到 D 盘的客服程序文件。", "微信客服");
            return;
        }
        string command = "$ErrorActionPreference='Stop'; try { & '" + script + "' } " +
            "catch { Add-Type -AssemblyName System.Windows.Forms; " +
            "[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'微信客服'); exit 1 }";
        var start = new ProcessStartInfo {
            FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
            Arguments = "-NoProfile -ExecutionPolicy RemoteSigned -EncodedCommand " +
                Convert.ToBase64String(System.Text.Encoding.Unicode.GetBytes(command)),
            WorkingDirectory = root,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        try { Process.Start(start); }
        catch (Exception e) { MessageBox.Show(e.Message, "微信客服"); }
    }
}
