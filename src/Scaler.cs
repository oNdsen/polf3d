// POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

// The ONLY C# in the renderer.
//
// The 1992 original was written in C, with just the innermost pixel loops (the
// "scalers") in hand-written assembler. POLF3D mirrors that split: everything
// is PowerShell, except these few pixel loops, which PowerShell cannot run fast
// enough (64'000 pixels per frame).
//
// Textures and sprites are 64x64 int[] (ARGB, row-major). A value of 0 is transparent.
// "fog" is 0..256: how far a pixel is blended towards FogColor (distance haze).

public static class PolfScaler
{
    public static int FogColor = unchecked((int)0xFF101010);

    static int Mix(int c, int fog)
    {
        if (fog <= 0) return c;
        int r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
        int fr = (FogColor >> 16) & 255, fg = (FogColor >> 8) & 255, fb = FogColor & 255;
        r += ((fr - r) * fog) >> 8; g += ((fg - g) * fog) >> 8; b += ((fb - b) * fog) >> 8;
        return unchecked((int)0xFF000000) | (r << 16) | (g << 8) | b;
    }

    // Draws one vertical wall strip, w pixels wide, projected height h, centred vertically.
    // With alpha = true, texels of value 0 are skipped (windows drawn over the scene behind them).
    public static void Wall(int[] fb, int fbW, int fbH, int x, int w, int h, int[] tex, int texX, int fog, bool alpha)
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
            if (alpha && c == 0) continue;
            c = Mix(c, fog);
            int row = y * fbW;
            for (int xx = x; xx < xe; xx++) fb[row + xx] = c;
        }
    }

    // Draws a square sprite of projected size `size`, centred on centerX. Columns hidden
    // behind a nearer wall (zbuf[x] < depth) are skipped. depth <= 0 disables the test
    // (used for the player's weapon).
    public static void Sprite(int[] fb, int fbW, int fbH, double[] zbuf, int[] tex, int centerX, int size, double depth, int fog)
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
                if (c != 0) fb[y * fbW + x] = Mix(c, fog);
            }
        }
    }

    // Textured floor and ceiling ("floor casting"): every screen row below the horizon lies at a
    // known distance, so the floor position is interpolated along the row; the ceiling mirrors it.
    // fogPerTile: fog units per tile of distance, capped at maxFog.
    public static void Floor(int[] fb, int fbW, int fbH, double px, double py, double dirX, double dirY,
                             double planeX, double planeY, double projH, int[] floorTex, int[] ceilTex,
                             double fogPerTile, int maxFog)
    {
        int half = fbH / 2;
        int horizon = Mix(FogColor, 256);
        for (int x = 0; x < fbW; x++) { fb[half * fbW + x] = horizon; if (half > 0) fb[(half - 1) * fbW + x] = horizon; }
        for (int y = half + 1; y < fbH; y++)
        {
            double rowDist = 0.5 * projH / (y - half);
            double stepX = rowDist * 2.0 * planeX / fbW, stepY = rowDist * 2.0 * planeY / fbW;
            double fx = px + rowDist * (dirX - planeX) + stepX * 0.5;
            double fy = py + rowDist * (dirY - planeY) + stepY * 0.5;
            int fog = (int)(rowDist * fogPerTile); if (fog > maxFog) fog = maxFog;
            int rowF = y * fbW, rowC = (fbH - 1 - y) * fbW;
            for (int x = 0; x < fbW; x++)
            {
                int tx = (int)(fx * 64.0) & 63, ty = (int)(fy * 64.0) & 63;
                fx += stepX; fy += stepY;
                int i = ty * 64 + tx;
                fb[rowF + x] = Mix(floorTex[i], fog);
                fb[rowC + x] = Mix(ceilTex[i], fog);
            }
        }
    }
}
