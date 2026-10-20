# probe.ps1 - dump every DDC/CI monitor's name, current input (VCP 0x60) and MCCS
# capability string. Paste the output into a GitHub issue to add a monitor to the
# compatibility table.
#   powershell -ExecutionPolicy Bypass -File tools\probe.ps1
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class AwProbe {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct PM { public IntPtr h; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string desc; }
  public delegate bool MonEnum(IntPtr hMon, IntPtr hdc, IntPtr rect, IntPtr lp);
  [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonEnum cb, IntPtr lp);
  [DllImport("dxva2.dll")] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, out uint n);
  [DllImport("dxva2.dll")] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint n, [Out] PM[] a);
  [DllImport("dxva2.dll")] public static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte vcp, out uint type, out uint cur, out uint max);
  [DllImport("dxva2.dll")] static extern bool GetCapabilitiesStringLength(IntPtr h, out uint n);
  [DllImport("dxva2.dll", CharSet=CharSet.Ansi)] static extern bool CapabilitiesRequestAndCapabilitiesReply(IntPtr h, System.Text.StringBuilder s, uint n);
  public static List<PM> Mons() {
    var all = new List<PM>();
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (hm, dc, r, lp) => {
      uint n; if (GetNumberOfPhysicalMonitorsFromHMONITOR(hm, out n) && n > 0) {
        var a = new PM[n]; if (GetPhysicalMonitorsFromHMONITOR(hm, n, a)) all.AddRange(a); }
      return true; }, IntPtr.Zero);
    return all;
  }
  public static string Caps(IntPtr h) {
    uint n; if (!GetCapabilitiesStringLength(h, out n)) return "(no reply)";
    var sb = new System.Text.StringBuilder((int)n);
    return CapabilitiesRequestAndCapabilitiesReply(h, sb, n) ? sb.ToString() : "(no reply)";
  }
}
"@

foreach ($m in [AwProbe]::Mons()) {
  $t = 0; $cur = 0; $max = 0
  $vcp = if ([AwProbe]::GetVCPFeatureAndVCPFeatureReply($m.h, 0x60, [ref]$t, [ref]$cur, [ref]$max)) { "0x{0:X4}" -f $cur } else { "n/a" }
  "monitor : $($m.desc)"
  "VCP 60  : $vcp"
  "caps    : $([AwProbe]::Caps($m.h))"
  ""
}
