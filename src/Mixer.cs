// POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

// A small software mixer on top of winmm's waveOut: up to 24 sounds at once, each with its own volume
// for the left and the right ear, plus one looping music track - mixed into 23 ms blocks by a feeder
// thread. Real-time sample mixing is one of the few things PowerShell really cannot do.

using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

public static class PolfMixer
{
    [StructLayout(LayoutKind.Sequential)]
    struct WaveFormat { public short Tag, Channels; public int Rate, BytesPerSec; public short BlockAlign, Bits, Extra; }

    [StructLayout(LayoutKind.Sequential)]
    struct WaveHeader { public IntPtr Data; public int Length, Recorded; public IntPtr User; public int Flags, Loops; public IntPtr Next, Reserved; }

    [DllImport("winmm.dll")] static extern int waveOutOpen(out IntPtr handle, int device, ref WaveFormat format, IntPtr callback, IntPtr instance, int flags);
    [DllImport("winmm.dll")] static extern int waveOutPrepareHeader(IntPtr handle, IntPtr header, int size);
    [DllImport("winmm.dll")] static extern int waveOutUnprepareHeader(IntPtr handle, IntPtr header, int size);
    [DllImport("winmm.dll")] static extern int waveOutWrite(IntPtr handle, IntPtr header, int size);
    [DllImport("winmm.dll")] static extern int waveOutReset(IntPtr handle);
    [DllImport("winmm.dll")] static extern int waveOutClose(IntPtr handle);

    const int Rate = 22050, Frames = 512, Buffers = 4, MaxVoices = 24, Done = 1;

    class Voice { public short[] Data; public double Pos, Step; public float Left, Right; public int Prio; }

    static readonly List<short[]> samples = new List<short[]>();
    static readonly List<double> steps = new List<double>();
    static readonly Voice[] voices = new Voice[MaxVoices];
    static readonly object gate = new object();
    static Voice music;
    static IntPtr device;
    static IntPtr[] headers, blocks;
    static Thread feeder;
    static volatile bool running;

    public static float SfxVolume = 1.0f, MusicVolume = 0.45f;

    public static bool Open()
    {
        if (running) return true;
        var format = new WaveFormat { Tag = 1, Channels = 2, Rate = Rate, BytesPerSec = Rate * 4, BlockAlign = 4, Bits = 16 };
        if (waveOutOpen(out device, -1, ref format, IntPtr.Zero, IntPtr.Zero, 0) != 0) return false;
        int size = Marshal.SizeOf(typeof(WaveHeader));
        headers = new IntPtr[Buffers]; blocks = new IntPtr[Buffers];
        for (int i = 0; i < Buffers; i++)
        {
            blocks[i] = Marshal.AllocHGlobal(Frames * 4);
            headers[i] = Marshal.AllocHGlobal(size);
            var header = new WaveHeader { Data = blocks[i], Length = Frames * 4 };
            Marshal.StructureToPtr(header, headers[i], false);
            waveOutPrepareHeader(device, headers[i], size);
            Fill(i);
        }
        running = true;
        feeder = new Thread(Feed) { IsBackground = true, Priority = ThreadPriority.AboveNormal, Name = "POLF mixer" };
        feeder.Start();
        return true;
    }

    public static void Close()
    {
        if (!running) return;
        running = false;
        feeder.Join(500);
        waveOutReset(device);
        int size = Marshal.SizeOf(typeof(WaveHeader));
        for (int i = 0; i < Buffers; i++) { waveOutUnprepareHeader(device, headers[i], size); Marshal.FreeHGlobal(headers[i]); Marshal.FreeHGlobal(blocks[i]); }
        waveOutClose(device);
        lock (gate) { Array.Clear(voices, 0, MaxVoices); music = null; }
    }

    // Mono PCM, 8 bit unsigned or 16 bit signed, at any rate. Returns the id to play it with.
    public static int Load(byte[] pcm, int offset, int length, int bits, int rate)
    {
        short[] data;
        if (bits == 8) { data = new short[length]; for (int i = 0; i < length; i++) data[i] = (short)((pcm[offset + i] - 128) << 8); }
        else { data = new short[length / 2]; Buffer.BlockCopy(pcm, offset, data, 0, data.Length * 2); }
        lock (gate) { samples.Add(data); steps.Add((double)rate / Rate); return samples.Count - 1; }
    }

    // A whole WAV file (mono PCM): finds the format and the data chunk wherever they are.
    public static int LoadWav(byte[] file)
    {
        int bits = 16, rate = Rate, pos = 12;
        while (pos + 8 <= file.Length)
        {
            string id = System.Text.Encoding.ASCII.GetString(file, pos, 4);
            int size = BitConverter.ToInt32(file, pos + 4);
            if (id == "fmt ") { rate = BitConverter.ToInt32(file, pos + 12); bits = BitConverter.ToInt16(file, pos + 22); }
            else if (id == "data") return Load(file, pos + 8, Math.Min(size, file.Length - pos - 8), bits, rate);
            pos += 8 + size + (size & 1);
        }
        return -1;
    }

    public static double Seconds(int id) { lock (gate) { return id < 0 || id >= samples.Count ? 0 : samples[id].Length / steps[id] / Rate; } }

    // Starts a sound. When all voices are busy the one with the lowest priority makes room - if it is lower.
    public static void Play(int id, float left, float right, int prio)
    {
        lock (gate)
        {
            if (id < 0 || id >= samples.Count) return;
            int slot = -1, weakest = -1;
            for (int i = 0; i < MaxVoices; i++)
            {
                if (voices[i] == null) { slot = i; break; }
                if (weakest < 0 || voices[i].Prio < voices[weakest].Prio) weakest = i;
            }
            if (slot < 0) { if (voices[weakest].Prio > prio) return; slot = weakest; }
            voices[slot] = new Voice { Data = samples[id], Step = steps[id], Left = left, Right = right, Prio = prio };
        }
    }

    public static void SetMusic(int id) { lock (gate) { music = id < 0 || id >= samples.Count ? null : new Voice { Data = samples[id], Step = steps[id], Left = 1, Right = 1 }; } }

    static void Feed()
    {
        while (running)
        {
            for (int i = 0; i < Buffers; i++) if ((Marshal.ReadInt32(headers[i], (int)Marshal.OffsetOf(typeof(WaveHeader), "Flags")) & Done) != 0) Fill(i);
            Thread.Sleep(4);
        }
    }

    static readonly int[] mixL = new int[Frames], mixR = new int[Frames];
    static readonly short[] block = new short[Frames * 2];

    static void Fill(int index)
    {
        Array.Clear(mixL, 0, Frames); Array.Clear(mixR, 0, Frames);
        lock (gate)
        {
            if (music != null && music.Data.Length > 0)
            {
                float v = MusicVolume;
                for (int f = 0; f < Frames; f++)
                {
                    int s = (int)(music.Data[(int)music.Pos] * v);
                    mixL[f] += s; mixR[f] += s;
                    music.Pos += music.Step; if (music.Pos >= music.Data.Length) music.Pos -= music.Data.Length;      // round and round
                }
            }
            for (int i = 0; i < MaxVoices; i++)
            {
                Voice voice = voices[i];
                if (voice == null) continue;
                float l = voice.Left * SfxVolume, r = voice.Right * SfxVolume;
                for (int f = 0; f < Frames; f++)
                {
                    if (voice.Pos >= voice.Data.Length) { voices[i] = null; break; }
                    short s = voice.Data[(int)voice.Pos];
                    mixL[f] += (int)(s * l); mixR[f] += (int)(s * r);
                    voice.Pos += voice.Step;
                }
            }
        }
        for (int f = 0; f < Frames; f++)
        {
            int l = mixL[f], r = mixR[f];
            block[2 * f] = (short)(l > 32767 ? 32767 : l < -32768 ? -32768 : l);
            block[2 * f + 1] = (short)(r > 32767 ? 32767 : r < -32768 ? -32768 : r);
        }
        Marshal.Copy(block, 0, blocks[index], Frames * 2);
        waveOutWrite(device, headers[index], Marshal.SizeOf(typeof(WaveHeader)));
    }
}
