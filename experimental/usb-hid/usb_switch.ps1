param([string]$Target = "hdmi1", [int]$RevertAfter = 10)
# AW3225QF input switch over the monitor's USB HID-to-I2C bridge (Microchip USB5734T).
$log = Join-Path $PSScriptRoot "aw_switch_log.txt"
Remove-Item $log -ErrorAction SilentlyContinue

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class AwHid {
  [StructLayout(LayoutKind.Sequential)] struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid g; public int Flags; public IntPtr Reserved; }
  [StructLayout(LayoutKind.Sequential)] struct HIDD_ATTRIBUTES { public int Size; public ushort VendorID; public ushort ProductID; public ushort Version; }
  [StructLayout(LayoutKind.Sequential)] struct HIDP_CAPS { public ushort Usage, UsagePage, InLen, OutLen, FeatLen; [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)] public ushort[] r; public ushort a,b,c,d,e,f,g,h,i,j; }
  [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
  [DllImport("hid.dll")] static extern bool HidD_GetAttributes(SafeFileHandle h, ref HIDD_ATTRIBUTES a);
  [DllImport("hid.dll")] static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr p);
  [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr p);
  [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr p, ref HIDP_CAPS c);
  [DllImport("setupapi.dll", CharSet=CharSet.Auto)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr w, int f);
  [DllImport("setupapi.dll")] static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, int i, ref SP_DEVICE_INTERFACE_DATA x);
  [DllImport("setupapi.dll", CharSet=CharSet.Auto)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref SP_DEVICE_INTERFACE_DATA x, IntPtr d, int sz, out int req, IntPtr di);
  [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)] static extern SafeFileHandle CreateFile(string n, uint a, uint s, IntPtr sa, uint c, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool WriteFile(SafeFileHandle h, IntPtr b, int n, IntPtr w, IntPtr ov);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadFile(SafeFileHandle h, IntPtr b, int n, IntPtr r, IntPtr ov);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetOverlappedResult(SafeFileHandle h, IntPtr ov, out int n, bool wait);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool CancelIoEx(SafeFileHandle h, IntPtr ov);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateEvent(IntPtr a, bool manual, bool init, string n);
  [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
  static int Xfer(bool write, byte[] data, uint ms) {
    IntPtr buf = Marshal.AllocHGlobal(data.Length); IntPtr ov = Marshal.AllocHGlobal(32);
    for (int i = 0; i < 32; i++) Marshal.WriteByte(ov, i, 0);
    IntPtr ev = CreateEvent(IntPtr.Zero, true, false, null); Marshal.WriteIntPtr(ov, 24, ev);
    Marshal.Copy(data, 0, buf, data.Length);
    bool ok = write ? WriteFile(dev, buf, data.Length, IntPtr.Zero, ov) : ReadFile(dev, buf, data.Length, IntPtr.Zero, ov);
    int err = Marshal.GetLastWin32Error(), n = -1;
    if (ok || err == 997) {
      if (WaitForSingleObject(ev, ms) == 0) { if (GetOverlappedResult(dev, ov, out n, false)) { if (!write) Marshal.Copy(buf, data, 0, data.Length); } else { n = -1000 - Marshal.GetLastWin32Error(); } }
      else { CancelIoEx(dev, ov); GetOverlappedResult(dev, ov, out n, true); n = -2; }
    } else n = -1000 - err;
    Marshal.FreeHGlobal(buf); Marshal.FreeHGlobal(ov);
    return n;
  }

  [DllImport("hid.dll")] static extern bool HidD_SetOutputReport(SafeFileHandle h, byte[] b, int len);
  public static string LogPath;
  public static void L(string m) { File.AppendAllText(LogPath, DateTime.Now.ToString("HH:mm:ss.fff ") + m + "\r\n"); }
  static SafeFileHandle dev; static int outLen, inLen; static byte[] rbuf;

  public static List<string> Paths() {
    var res = new List<string>(); Guid g; HidD_GetHidGuid(out g);
    IntPtr set = SetupDiGetClassDevs(ref g, IntPtr.Zero, IntPtr.Zero, 0x12);
    var d = new SP_DEVICE_INTERFACE_DATA(); d.cbSize = Marshal.SizeOf(d);
    for (int i = 0; SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref g, i, ref d); i++) {
      int req; SetupDiGetDeviceInterfaceDetail(set, ref d, IntPtr.Zero, 0, out req, IntPtr.Zero);
      IntPtr buf = Marshal.AllocHGlobal(req);
      Marshal.WriteInt32(buf, IntPtr.Size == 8 ? 8 : 6);
      if (SetupDiGetDeviceInterfaceDetail(set, ref d, buf, req, out req, IntPtr.Zero))
        res.Add(Marshal.PtrToStringAuto(new IntPtr(buf.ToInt64() + 4)));
      Marshal.FreeHGlobal(buf);
    }
    return res;
  }

  public static bool Open(ushort vid, ushort pid) {
    foreach (var p in Paths()) {
      if (!p.ToLower().Contains(String.Format("vid_{0:x4}&pid_{1:x4}", vid, pid))) continue;
      var h = CreateFile(p, 0xC0000000, 3, IntPtr.Zero, 3, 0x40000000, IntPtr.Zero);  // OVERLAPPED
      if (h.IsInvalid) { L("cannot open " + p + " err " + Marshal.GetLastWin32Error()); continue; }
      IntPtr pp; HidD_GetPreparsedData(h, out pp);
      var c = new HIDP_CAPS(); HidP_GetCaps(pp, ref c); HidD_FreePreparsedData(pp);
      L(String.Format("candidate {0} usagePage=0x{1:X4} in={2} out={3}", p, c.UsagePage, c.InLen, c.OutLen));
      if (c.OutLen == 65) { dev = h; outLen = c.OutLen; inLen = c.InLen; return true; }
      h.Dispose();
    }
    return false;
  }

  public static List<string> ListIds() {
    var s = new List<string>();
    foreach (var p in Paths()) { var l = p.ToLower(); int i = l.IndexOf("vid_"); if (i >= 0) s.Add(l.Substring(i, Math.Min(30, l.Length - i))); }
    return s;
  }

  static void Send(byte[] pkt) {
    var b = new byte[outLen]; for (int i = 0; i < b.Length; i++) b[i] = 0xFF;
    Array.Copy(pkt, b, pkt.Length);
    L("TX " + BitConverter.ToString(b, 0, 16));
    int n = Xfer(true, b, 2000);
    L("  WriteFile -> " + n + (n == -2 ? " (timeout)" : n < -1000 ? " (win32 err " + (-n - 1000) + ")" : ""));
    if (n != b.Length) {
      L("WriteFile did not complete, trying HidD_SetOutputReport");
      bool r = HidD_SetOutputReport(dev, b, b.Length);
      L("HidD_SetOutputReport -> " + r + " err " + Marshal.GetLastWin32Error());
    }
  }
  static byte[] Recv(int ms) {
    rbuf = new byte[inLen];
    int n = Xfer(false, rbuf, (uint)ms);
    L("  ReadFile -> " + n);
    if (n <= 0) return null;
    L("RX " + BitConverter.ToString(rbuf, 0, Math.Min(24, rbuf.Length)));
    return rbuf;
  }

  public static void Config() { Send(new byte[] { 0x00, 0x95, 0, 0, 0, 0, 0, 0, 0 }); }

  static void I2CWrite(byte[] data) {
    var p = new byte[5 + data.Length]; p[0] = 0; p[1] = 0x92; p[2] = 0x37; p[3] = (byte)data.Length; p[4] = 0;
    Array.Copy(data, 0, p, 5, data.Length); Send(p); System.Threading.Thread.Sleep(50);
  }

  public static void SetVcp(byte vcp, int val) {
    byte[] d = { 0x51, 0x84, 0x03, vcp, (byte)(val >> 8), (byte)val, 0 };
    byte c = 0x6E; for (int i = 0; i < 6; i++) c ^= d[i]; d[6] = c;
    I2CWrite(d);
  }

  public static int GetVcp(byte vcp) {
    byte[] d = { 0x51, 0x82, 0x01, vcp, 0 };
    byte c = 0x6E; for (int i = 0; i < 4; i++) c ^= d[i]; d[4] = c;
    I2CWrite(d); System.Threading.Thread.Sleep(40);
    Send(new byte[] { 0x00, 0x93, 0x37, 11, 0, 0, 0 });
    for (int tries = 0; tries < 4; tries++) {
      var r = Recv(1500); if (r == null) { L("read timeout"); return -1; }
      int o = (r[0] == 0x94) ? 0 : (r.Length > 1 && r[1] == 0x94 ? 1 : -1);
      if (o < 0) continue;
      int n = Math.Min((int)r[o + 2], r.Length - o - 4); var x = new byte[n]; Array.Copy(r, o + 4, x, 0, n);
      L("DDC reply " + BitConverter.ToString(x));
      if (n >= 10 && x[2] == 0x02) return (x[8] << 8) | x[9];
      return -2;
    }
    return -3;
  }
}
"@

$codes = @{ dp = 0x0F; hdmi1 = 0x11; hdmi2 = 0x12 }
[AwHid]::LogPath = $log
function Log($m) { [AwHid]::L($m) }
trap { Log ("EXCEPTION: " + $_.Exception.ToString()); exit 2 }
Log "AW3225QF switch test v2  target=$Target  revertAfter=${RevertAfter}s"

$ok = $false
foreach ($id in @(@(0x187C, 0x1013), @(0x0424, 0x274C))) {
  if ([AwHid]::Open($id[0], $id[1])) { Log ("Opened bridge {0:X4}:{1:X4}" -f $id[0], $id[1]); $ok = $true; break }
}
if (-not $ok) { Log "Bridge NOT found. HID devices present:"; [AwHid]::ListIds() | Sort-Object -Unique | ForEach-Object { Log $_ }; exit 1 }

[AwHid]::Config()
$c = $codes[$Target]; $v = ($c -shl 8) -bor $c
Log ("Sending input switch -> $Target (0x{0:X4})" -f $v)
[AwHid]::SetVcp(0x60, $v)
Log "Switch sent. Reading back in 3s..."
Start-Sleep -Seconds 3
$cur = [AwHid]::GetVcp(0x60); Log ("After:  VCP60 = 0x{0:X4}" -f $cur)
if ($RevertAfter -gt 0) {
  Start-Sleep -Seconds $RevertAfter
  Log "Reverting -> dp"
  [AwHid]::SetVcp(0x60, 0x0F0F)
  Start-Sleep -Seconds 3
  $cur = [AwHid]::GetVcp(0x60); Log ("Final:  VCP60 = 0x{0:X4}" -f $cur)
}
Log "done"
