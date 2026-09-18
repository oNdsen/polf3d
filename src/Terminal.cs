// POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

// Terminal mode (-Terminal): the third and last piece of C#. One loop that turns the frame buffer into
// half-block characters with 24 bit colours (8,000 cells a frame are too many for PowerShell), and the
// declaration PowerShell needs to ask Windows which keys are down - a console only ever reports key
// presses, never releases.

using System;
using System.Runtime.InteropServices;
using System.Text;

public static class PolfTerminal
{
    [DllImport("user32.dll")]
    static extern short GetAsyncKeyState(int vKey);

    public static bool IsDown(int vKey) { return (GetAsyncKeyState(vKey) & 0x8000) != 0; }

    // Every character cell shows two pixels: the upper one as the colour of a "▀", the lower one as its
    // background. Colours are only written when they change. tint = AARRGGBB laid over the picture.
    public static void Ansi(int[] fb, int fbW, int fbH, int cols, int rows, int indent, int tint, StringBuilder sb)
    {
        int ta = (tint >> 24) & 255, tr = (tint >> 16) & 255, tg = (tint >> 8) & 255, tb = tint & 255;
        for (int r = 0; r < rows; r++)
        {
            int yTop = (2 * r) * fbH / (2 * rows), yBottom = (2 * r + 1) * fbH / (2 * rows);
            int lastFg = -1, lastBg = -1;
            if (indent > 0) sb.Append(' ', indent);
            for (int c = 0; c < cols; c++)
            {
                int x = c * fbW / cols;
                int fg = Shade(fb[yTop * fbW + x], ta, tr, tg, tb), bg = Shade(fb[yBottom * fbW + x], ta, tr, tg, tb);
                if (fg != lastFg) { sb.Append("\x1b[38;2;").Append((fg >> 16) & 255).Append(';').Append((fg >> 8) & 255).Append(';').Append(fg & 255).Append('m'); lastFg = fg; }
                if (bg != lastBg) { sb.Append("\x1b[48;2;").Append((bg >> 16) & 255).Append(';').Append((bg >> 8) & 255).Append(';').Append(bg & 255).Append('m'); lastBg = bg; }
                sb.Append('▀');
            }
            sb.Append("\x1b[0m\x1b[K\n");
        }
    }

    static int Shade(int c, int ta, int tr, int tg, int tb)
    {
        int r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
        if (ta > 0) { r += (tr - r) * ta / 255; g += (tg - g) * ta / 255; b += (tb - b) * ta / 255; }
        return ((r & 0xF8) << 16) | ((g & 0xF8) << 8) | (b & 0xF8);        // a slightly coarser palette: longer runs, less to write
    }
}
