// POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

// The ONLY C# in POLF3D.
//
// The 1992 original was written in C, with just the innermost pixel loops (the
// "scalers") in hand-written assembler. POLF3D mirrors that split: everything
// is PowerShell, except these two pixel loops, which PowerShell cannot run fast
// enough (64'000 pixels per frame).
//
// Textures and sprites are 64x64 int[] (ARGB, row-major). A value of 0 is transparent.

public static class PolfScaler
{
    // Draws one vertical wall strip, w pixels wide, projected height h, centred vertically.
    public static void Wall(int[] fb, int fbW, int fbH, int x, int w, int h, int[] tex, int texX)
    {
        if (h < 1) h = 1;
        int top = (fbH - h) / 2;
        int y0 = top < 0 ? 0 : top;
        int y1 = top + h; if (y1 > fbH) y1 = fbH;
        int xe = x + w;   if (xe > fbW) xe = fbW;
        long step = (64L << 16) / h;
        long pos = (long)(y0 - top) * step;
        texX &= 63;
        for (int y = y0; y < y1; y++)
        {
            int c = tex[(int)((pos >> 16) & 63) * 64 + texX];
            pos += step;
            int row = y * fbW;
            for (int xx = x; xx < xe; xx++) fb[row + xx] = c;
        }
    }

    // Draws a square sprite of projected size `size`, centred on centerX. Columns hidden
    // behind a nearer wall (zbuf[x] < depth) are skipped. depth <= 0 disables the test
    // (used for the player's weapon).
    public static void Sprite(int[] fb, int fbW, int fbH, double[] zbuf, int[] tex, int centerX, int size, double depth)
    {
        if (size < 1) return;
        int left = centerX - size / 2;
        int top = (fbH - size) / 2;
        int x0 = left < 0 ? 0 : left;
        int x1 = left + size; if (x1 > fbW) x1 = fbW;
        int y0 = top < 0 ? 0 : top;
        int y1 = top + size; if (y1 > fbH) y1 = fbH;
        long step = (64L << 16) / size;
        for (int x = x0; x < x1; x++)
        {
            if (depth > 0 && zbuf[x] < depth) continue;
            int texX = (int)(((long)(x - left) * step) >> 16) & 63;
            long pos = (long)(y0 - top) * step;
            for (int y = y0; y < y1; y++)
            {
                int c = tex[(int)((pos >> 16) & 63) * 64 + texX];
                pos += step;
                if (c != 0) fb[y * fbW + x] = c;
            }
        }
    }
}
