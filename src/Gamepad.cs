// POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

// XInput game pad access. PowerShell cannot call into a native DLL by itself, so this is the
// second (and last) piece of C#: one P/Invoke declaration and a little normalisation.

using System;
using System.Runtime.InteropServices;

public static class PolfGamepad
{
    [StructLayout(LayoutKind.Sequential)]
    struct State
    {
        public uint Packet;
        public ushort Buttons;
        public byte LeftTrigger, RightTrigger;
        public short LX, LY, RX, RY;
    }

    [DllImport("xinput1_4.dll", EntryPoint = "XInputGetState")]
    static extern uint GetState14(uint index, out State state);

    [DllImport("xinput9_1_0.dll", EntryPoint = "XInputGetState")]
    static extern uint GetState910(uint index, out State state);

    static bool useOld;

    static double Axis(short v, double deadZone)
    {
        double d = v / 32767.0;
        if (Math.Abs(d) < deadZone) return 0.0;
        return Math.Sign(d) * (Math.Abs(d) - deadZone) / (1.0 - deadZone);
    }

    // Returns null when no pad is connected, otherwise
    // { leftX, leftY, rightX, rightY, leftTrigger, rightTrigger, buttons } with axes in -1..1.
    public static double[] Read(int index)
    {
        State s; uint rc;
        try { rc = useOld ? GetState910((uint)index, out s) : GetState14((uint)index, out s); }
        catch (DllNotFoundException)
        {
            if (useOld) return null;
            useOld = true;
            try { rc = GetState910((uint)index, out s); } catch (DllNotFoundException) { return null; }
        }
        if (rc != 0) return null;
        return new double[] {
            Axis(s.LX, 0.24), Axis(s.LY, 0.24), Axis(s.RX, 0.20), Axis(s.RY, 0.20),
            s.LeftTrigger / 255.0, s.RightTrigger / 255.0, s.Buttons };
    }
}
