// awinput - switch Dell / Alienware monitor inputs from the command line (DDC/CI VCP 0x60).
// https://github.com/<you>/awinput  -  MIT License
//
// Built as a windowless exe so Stream Deck / hotkey launchers don't flash a console.
// When started from a terminal it attaches to that console for its output.
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

static class AwInput {
    const string Version = "1.0.0";

    // ---- Win32 / dxva2 ------------------------------------------------------------
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct PM { public IntPtr h; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string desc; }
    delegate bool MonEnum(IntPtr hMon, IntPtr hdc, IntPtr rect, IntPtr lp);
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonEnum cb, IntPtr lp);
    [DllImport("dxva2.dll")] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, out uint n);
    [DllImport("dxva2.dll")] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint n, [Out] PM[] a);
    [DllImport("dxva2.dll")] static extern bool DestroyPhysicalMonitors(uint n, PM[] a);
    [DllImport("dxva2.dll")] static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte vcp, out uint type, out uint cur, out uint max);
    [DllImport("dxva2.dll")] static extern bool SetVCPFeature(IntPtr h, byte vcp, uint val);
    [DllImport("dxva2.dll")] static extern bool GetCapabilitiesStringLength(IntPtr h, out uint n);
    [DllImport("dxva2.dll", CharSet = CharSet.Ansi)] static extern bool CapabilitiesRequestAndCapabilitiesReply(IntPtr h, System.Text.StringBuilder s, uint n);
    [DllImport("kernel32.dll")] static extern bool AttachConsole(int pid);

    const byte VCP_INPUT = 0x60;

    // MCCS 2.2 input source codes (VCP 0x60). Dell/Alienware use these.
    static readonly Dictionary<string, uint> Inputs = new Dictionary<string, uint>(StringComparer.OrdinalIgnoreCase) {
        { "vga", 0x01 }, { "dvi", 0x03 }, { "dvi2", 0x04 },
        { "dp", 0x0F }, { "dp1", 0x0F }, { "dp2", 0x10 },
        { "hdmi", 0x11 }, { "hdmi1", 0x11 }, { "hdmi2", 0x12 },
        { "usbc", 0x1B }, { "typec", 0x1B },
    };

    static string NameOf(uint code) {
        switch (code) {
            case 0x01: return "VGA"; case 0x03: return "DVI-1"; case 0x04: return "DVI-2";
            case 0x0F: return "DP-1"; case 0x10: return "DP-2";
            case 0x11: return "HDMI-1"; case 0x12: return "HDMI-2"; case 0x1B: return "USB-C";
            default: return "0x" + code.ToString("X2");
        }
    }

    // ---- output -------------------------------------------------------------------
    static bool hasConsole;
    static readonly string LogPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "awinput.log");
    static void Out(string m) { if (hasConsole) Console.WriteLine(m); }
    static void Err(string m) {
        if (hasConsole) Console.Error.WriteLine("awinput: " + m);
        try { File.AppendAllText(LogPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss ") + m + "\r\n"); } catch { }
    }

    const string Usage =
@"awinput " + Version + @" - switch Dell / Alienware monitor inputs over DDC/CI

usage: awinput <command> [options]

commands:
  dp | dp2 | hdmi1 | hdmi2 | usbc     switch to that input
  0xNN                                switch to a raw VCP 0x60 code
  toggle [A] [B]                      flip between two inputs (default: dp hdmi1)
  cycle  [A B C ...]                  step through inputs (default: inputs the monitor reports)
  get                                 print the active input
  list                                list monitors, their current input and supported inputs
  caps                                print raw MCCS capability strings

options:
  -m, --monitor NAME   pick the monitor whose name contains NAME (default: first Alienware/Dell)
  --plain              send 0x00NN (plain MCCS) instead of Dell's 0xNNNN form
  -h, --help           show this help

Errors are also written to awinput.log next to the exe (useful from Stream Deck).";

    static int Main(string[] argv) {
        hasConsole = AttachConsole(-1);
        try { return Run(argv); }
        catch (Exception e) { Err("unexpected error: " + e.Message); return 10; }
        finally { if (hasConsole) Console.WriteLine(); }
    }

    static int Run(string[] argv) {
        string want = null; bool plain = false;
        var pos = new List<string>();
        for (int i = 0; i < argv.Length; i++) {
            string a = argv[i];
            if (a == "-m" || a == "--monitor") { if (++i >= argv.Length) { Err("--monitor needs a name"); return 1; } want = argv[i]; }
            else if (a == "--plain") plain = true;
            else if (a == "-h" || a == "--help" || a == "/?") { Out(Usage); return 0; }
            else if (a == "--version") { Out(Version); return 0; }
            else pos.Add(a);
        }
        if (pos.Count == 0) { Out(Usage); return 1; }
        string cmd = pos[0].ToLowerInvariant();

        var mons = Enumerate();
        try {
            if (cmd == "list") { foreach (var m in mons) Out(Describe(m)); if (mons.Count == 0) Out("no DDC/CI monitors found"); return 0; }
            if (cmd == "caps") { foreach (var m in mons) Out(m.desc + ": " + (Caps(m.h) ?? "(no reply)")); return 0; }

            PM? sel = Pick(mons, want);
            if (sel == null) {
                Err(want == null ? "no Dell/Alienware monitor found (use --monitor NAME; see 'awinput list')"
                                 : "no monitor matching '" + want + "' (see 'awinput list')");
                return 2;
            }
            PM mon = sel.Value;

            if (cmd == "get") {
                uint cur;
                if (!ReadInput(mon.h, out cur)) { Err("could not read the current input of " + mon.desc); return 3; }
                Out(NameOf(cur & 0xFF));
                return 0;
            }

            uint code;
            if (cmd == "toggle") {
                uint a = 0x0F, b = 0x11;
                if (pos.Count >= 3 && (!TryCode(pos[1], out a) || !TryCode(pos[2], out b))) { Err("toggle: unknown input"); return 1; }
                uint cur;
                if (!ReadInput(mon.h, out cur)) { Err("could not read the current input of " + mon.desc); return 3; }
                code = (cur & 0xFF) == a ? b : a;
            } else if (cmd == "cycle") {
                var list = new List<uint>();
                for (int i = 1; i < pos.Count; i++) { uint c; if (!TryCode(pos[i], out c)) { Err("cycle: unknown input '" + pos[i] + "'"); return 1; } list.Add(c); }
                if (list.Count == 0) list = SupportedInputs(mon.h);
                if (list.Count == 0) list = new List<uint> { 0x0F, 0x11, 0x12 };
                uint cur;
                if (!ReadInput(mon.h, out cur)) { Err("could not read the current input of " + mon.desc); return 3; }
                int idx = list.IndexOf(cur & 0xFF);
                code = list[(idx + 1) % list.Count];
            } else if (!TryCode(cmd, out code)) {
                Err("unknown command '" + pos[0] + "' (try --help)"); return 1;
            }

            // Dell's own firmware tool writes the input code into both bytes (0xNNNN).
            uint value = plain ? code : (code << 8) | code;
            if (!SetVCPFeature(mon.h, VCP_INPUT, value) && !(!plain && SetVCPFeature(mon.h, VCP_INPUT, code))) {
                Err("SetVCPFeature failed on " + mon.desc); return 4;
            }
            Out(mon.desc + " -> " + NameOf(code));
            return 0;
        } finally {
            if (mons.Count > 0) DestroyPhysicalMonitors((uint)mons.Count, mons.ToArray());
        }
    }

    // ---- helpers ------------------------------------------------------------------
    static List<PM> Enumerate() {
        var all = new List<PM>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate (IntPtr hm, IntPtr dc, IntPtr r, IntPtr lp) {
            uint n;
            if (GetNumberOfPhysicalMonitorsFromHMONITOR(hm, out n) && n > 0) {
                var a = new PM[n];
                if (GetPhysicalMonitorsFromHMONITOR(hm, n, a)) all.AddRange(a);
            }
            return true;
        }, IntPtr.Zero);
        return all;
    }

    static PM? Pick(List<PM> mons, string want) {
        if (want != null) {
            foreach (var m in mons) if (Has(m.desc, want)) return m;
            // Generic PnP names hide the model; fall back to the capability string.
            foreach (var m in mons) if (Has(Caps(m.h), "model(" + want)) return m;
            return null;
        }
        foreach (var m in mons) if (Has(m.desc, "Alienware") || Has(m.desc, "Dell")) return m;
        foreach (var m in mons) { string c = Caps(m.h); if (Has(c, "model(AW") || Has(c, "model(U") || Has(c, "model(S") || Has(c, "model(P") || Has(c, "model(G")) return m; }
        return null;
    }

    static bool Has(string s, string sub) { return s != null && s.IndexOf(sub, StringComparison.OrdinalIgnoreCase) >= 0; }

    static bool TryCode(string s, out uint code) {
        if (Inputs.TryGetValue(s, out code)) return true;
        if (s.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) {
            try { code = Convert.ToUInt32(s.Substring(2), 16) & 0xFF; return true; } catch { }
        }
        code = 0; return false;
    }

    static bool ReadInput(IntPtr h, out uint cur) {
        uint t, max;
        for (int i = 0; i < 3; i++) {   // DDC/CI reads are occasionally flaky; retry
            if (GetVCPFeatureAndVCPFeatureReply(h, VCP_INPUT, out t, out cur, out max)) return true;
            System.Threading.Thread.Sleep(50);
        }
        cur = 0; return false;
    }

    static string Caps(IntPtr h) {
        uint n;
        if (!GetCapabilitiesStringLength(h, out n) || n == 0) return null;
        var sb = new System.Text.StringBuilder((int)n);
        return CapabilitiesRequestAndCapabilitiesReply(h, sb, n) ? sb.ToString() : null;
    }

    // Parse "60( 0F 11 12)" out of the MCCS capability string.
    static List<uint> SupportedInputs(IntPtr h) {
        var res = new List<uint>();
        string c = Caps(h);
        if (c == null) return res;
        int v = c.IndexOf("vcp(", StringComparison.OrdinalIgnoreCase);
        int i = v < 0 ? -1 : c.IndexOf("60(", v, StringComparison.OrdinalIgnoreCase);
        if (i < 0) return res;
        int j = c.IndexOf(')', i);
        if (j < 0) return res;
        foreach (var tok in c.Substring(i + 3, j - i - 3).Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries)) {
            try { res.Add(Convert.ToUInt32(tok, 16)); } catch { }
        }
        return res;
    }

    static string Describe(PM m) {
        uint cur;
        string now = ReadInput(m.h, out cur) ? NameOf(cur & 0xFF) : "n/a";
        var sup = SupportedInputs(m.h);
        var names = new List<string>();
        foreach (var s in sup) names.Add(NameOf(s));
        return string.Format("{0}\n    current: {1}\n    inputs:  {2}", m.desc, now, names.Count > 0 ? string.Join(", ", names.ToArray()) : "(not reported)");
    }
}
