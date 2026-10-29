// ============================================================
//  Velocity · Lançador
//  Extrai o app (PowerShell + XAML) embutido em app.zip para
//  %ProgramData%\Velocity\app e abre a interface.
//
//  Segurança: o app roda como administrador, então a pasta de onde
//  ele é carregado precisa ser gravável SÓ por administradores.
//  Antes, "Usuários" podiam criar arquivos em app\Modules, e o Velocity
//  carrega todo .ps1 de lá — qualquer programa sem privilégio podia
//  colocar código ali e ganhar acesso de administrador.
// ============================================================
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;

static class Program
{
    [STAThread]
    static void Main()
    {
        try
        {
            string version = ((AssemblyInformationalVersionAttribute)Attribute.GetCustomAttribute(
                Assembly.GetExecutingAssembly(), typeof(AssemblyInformationalVersionAttribute))).InformationalVersion;

            string dataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Velocity");
            string appDir = Path.Combine(dataDir, "app");
            string stamp = Path.Combine(appDir, ".build");

            Directory.CreateDirectory(dataDir);
            Protect(dataDir);

            // Com o Velocity já aberto, não mexe nos arquivos (o script avisa que já está aberto)
            Mutex running;
            bool alreadyOpen = Mutex.TryOpenExisting(@"Global\VelocityGameOptimizer", out running);
            if (running != null) running.Dispose();

            if (!alreadyOpen)
            {
                // Extrai sempre: garante que os scripts executados são exatamente os deste exe
                Extract(appDir);
                File.WriteAllText(stamp, version);
            }
            else if (!File.Exists(stamp) || File.ReadAllText(stamp) != version)
            {
                throw new IOException("Feche o Velocity que já está aberto e tente novamente.");
            }

            string powershell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            string script = Path.Combine(appDir, "Velocity.ps1");
            var psi = new ProcessStartInfo(powershell,
                "-NoProfile -NoLogo -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"");
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = appDir;
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Não foi possível iniciar o Velocity.\n\n" + ex.Message, "Velocity",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    // SYSTEM e Administradores: controle total. Usuários: só leitura.
    // Sem herança da ProgramData (que deixa qualquer usuário criar arquivos).
    static void Protect(string dir)
    {
        var system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
        var admins = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
        var users = new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null);
        var inherit = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;

        var acl = new DirectorySecurity();
        acl.SetAccessRuleProtection(true, false);
        acl.AddAccessRule(new FileSystemAccessRule(system, FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
        acl.AddAccessRule(new FileSystemAccessRule(admins, FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
        acl.AddAccessRule(new FileSystemAccessRule(users, FileSystemRights.ReadAndExecute, inherit, PropagationFlags.None, AccessControlType.Allow));
        Directory.SetAccessControl(dir, acl);

        // O dono de uma pasta sempre pode trocar as permissões dela: passa a ser Administradores
        try
        {
            var owner = new DirectorySecurity();
            owner.SetOwner(admins);
            Directory.SetAccessControl(dir, owner);
        }
        catch (Exception) { }
    }

    static void Extract(string appDir)
    {
        if (Directory.Exists(appDir))
        {
            try { Directory.Delete(appDir, true); }
            catch (Exception) { throw new IOException("Feche o Velocity que já está aberto e tente novamente."); }
        }
        Directory.CreateDirectory(appDir);
        string root = Path.GetFullPath(appDir) + Path.DirectorySeparatorChar;

        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("app.zip"))
        using (var zip = new ZipArchive(stream, ZipArchiveMode.Read))
        {
            foreach (ZipArchiveEntry entry in zip.Entries)
            {
                string target = Path.GetFullPath(Path.Combine(appDir, entry.FullName.Replace('/', Path.DirectorySeparatorChar)));
                if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase)) continue;   // nada fora da pasta do app
                if (entry.Name.Length == 0) { Directory.CreateDirectory(target); continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                entry.ExtractToFile(target, true);
            }
        }
    }
}
