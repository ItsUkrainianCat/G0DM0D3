#!/usr/bin/env python3
"""Generate G0DM0D3 PNG icons without any dependencies (pure Python PNG writer)."""
import struct, zlib, os

def create_png(width, height, pixels):
    """Create a PNG file from RGBA pixel data."""
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    raw = b''
    for y in range(height):
        raw += b'\x00'  # filter: none
        for x in range(width):
            raw += bytes(pixels[y][x])

    return (b'\x89PNG\r\n\x1a\n' +
            chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(raw, 9)) +
            chunk(b'IEND', b''))

def lerp(a, b, t):
    return int(a + (b - a) * t)

def generate_icon(size):
    """Generate the G0DM0D3 volcano icon at given size."""
    px = [[(0, 0, 0, 0)] * size for _ in range(size)]
    s = size / 192.0  # scale factor (designed at 192px)

    def put(x, y, r, g, b, a=255):
        ix, iy = int(x), int(y)
        if 0 <= ix < size and 0 <= iy < size:
            # alpha blend
            if px[iy][ix][3] > 0 and a < 255:
                old = px[iy][ix]
                af = a / 255.0
                nr = int(old[0] * (1-af) + r * af)
                ng = int(old[1] * (1-af) + g * af)
                nb = int(old[2] * (1-af) + b * af)
                px[iy][ix] = (nr, ng, nb, 255)
            else:
                px[iy][ix] = (r, g, b, a)

    def filled_circle(cx, cy, radius, r, g, b, a=255):
        for dy in range(int(-radius-1), int(radius+2)):
            for dx in range(int(-radius-1), int(radius+2)):
                if dx*dx + dy*dy <= radius*radius:
                    put(cx+dx, cy+dy, r, g, b, a)

    def filled_rect(x1, y1, x2, y2, r, g, b, a=255):
        for y in range(int(y1), int(y2)+1):
            for x in range(int(x1), int(x2)+1):
                put(x, y, r, g, b, a)

    # Background - dark with subtle radial gradient
    cx, cy = size//2, size//2
    max_dist = (cx*cx + cy*cy) ** 0.5
    for y in range(size):
        for x in range(size):
            d = ((x-cx)**2 + (y-cy)**2) ** 0.5 / max_dist
            bg = lerp(20, 8, d)
            px[y][x] = (bg, lerp(5, 2, d), bg//2, 255)

    # Rounded square background
    corner_r = int(32 * s)
    margin = int(8 * s)
    for y in range(margin, size - margin):
        for x in range(margin, size - margin):
            # Check corners
            in_rect = True
            corners = [
                (margin + corner_r, margin + corner_r),
                (size - margin - corner_r, margin + corner_r),
                (margin + corner_r, size - margin - corner_r),
                (size - margin - corner_r, size - margin - corner_r),
            ]
            for ccx, ccy in corners:
                if ((x < ccx and y < ccy and (x - ccx)**2 + (y - ccy)**2 > corner_r**2) or
                    (x > size - margin - corner_r and y < ccy and (x - (size-margin-corner_r))**2 + (y - ccy)**2 > corner_r**2) or
                    (x < ccx and y > size - margin - corner_r and (x - ccx)**2 + (y - (size-margin-corner_r))**2 > corner_r**2) or
                    (x > size - margin - corner_r and y > size - margin - corner_r and (x - (size-margin-corner_r))**2 + (y - (size-margin-corner_r))**2 > corner_r**2)):
                    in_rect = False
                    break
            if in_rect:
                d = ((x-cx)**2 + (y-cy)**2) ** 0.5 / max_dist
                px[y][x] = (lerp(15, 8, d), lerp(3, 1, d), lerp(12, 5, d), 255)

    # Eruption glow (top area)
    glow_cx, glow_cy = int(96*s), int(45*s)
    glow_rx, glow_ry = int(55*s), int(45*s)
    for y in range(size):
        for x in range(size):
            dx = (x - glow_cx) / glow_rx
            dy = (y - glow_cy) / glow_ry
            d = dx*dx + dy*dy
            if d < 1.0:
                intensity = int((1.0 - d) * 80)
                old = px[y][x]
                nr = min(255, old[0] + intensity)
                ng = min(255, old[1] + intensity // 4)
                px[y][x] = (nr, ng, old[2], 255)

    # Volcano body (triangle)
    vtop_y = int(58*s)
    vbot_y = int(160*s)
    vleft = int(28*s)
    vright = int(164*s)
    vcx = int(96*s)
    for y in range(vtop_y, vbot_y):
        t = (y - vtop_y) / (vbot_y - vtop_y)
        xl = int(vcx - (vcx - vleft) * t)
        xr = int(vcx + (vright - vcx) * t)
        for x in range(xl, xr):
            # Gradient from dark gray to near-black
            gray = lerp(68, 26, t)
            put(x, y, gray, gray, gray)

    # Green edge lines on volcano
    for y in range(vtop_y, vbot_y):
        t = (y - vtop_y) / (vbot_y - vtop_y)
        xl = int(vcx - (vcx - vleft) * t)
        xr = int(vcx + (vright - vcx) * t)
        put(xl, y, 0, 255, 65, 180)
        put(xl+1, y, 0, 255, 65, 80)
        put(xr, y, 0, 255, 65, 180)
        put(xr-1, y, 0, 255, 65, 80)

    # Crater (dark ellipse at top of volcano)
    crater_cx, crater_cy = int(96*s), int(62*s)
    crater_rx, crater_ry = int(18*s), int(7*s)
    for y in range(size):
        for x in range(size):
            dx = (x - crater_cx) / crater_rx
            dy = (y - crater_cy) / crater_ry
            d = dx*dx + dy*dy
            if d < 1.0:
                put(x, y, 26, 10, 10)
            elif d < 1.3:
                put(x, y, 255, 69, 0, 200)

    # Lava eruption (center plume)
    for y in range(int(15*s), int(62*s)):
        t = (y - 15*s) / (47*s)
        w = int(lerp(4, 14, t) * s)
        for dx in range(-w, w+1):
            x = int(96*s) + dx
            dist = abs(dx) / max(w, 1)
            r = lerp(255, 255, dist)
            g = lerp(204, 69, dist)
            b = lerp(0, 0, dist)
            a = int((1.0 - dist * 0.5) * 230 * (0.5 + 0.5 * t))
            put(x, y, r, g, b, a)

    # Lava splash particles
    particles = [
        (67*s, 22*s, 5*s), (125*s, 22*s, 5*s),
        (58*s, 30*s, 3*s), (134*s, 30*s, 3*s),
        (75*s, 15*s, 4*s), (117*s, 15*s, 4*s),
        (96*s, 10*s, 3*s),
    ]
    for pcx, pcy, pr in particles:
        filled_circle(int(pcx), int(pcy), int(pr), 255, 180, 0, 220)
        filled_circle(int(pcx), int(pcy), int(pr*0.6), 255, 230, 50, 255)

    # "G0D" text
    text_y = int(140*s)
    text_h = int(16*s)
    text_color = (0, 255, 65)  # matrix green

    # Simple blocky text rendering
    def draw_char_block(char_data, start_x, start_y, char_w, char_h):
        pw = max(1, char_w // len(char_data[0]))
        ph = max(1, char_h // len(char_data))
        for r, row in enumerate(char_data):
            for c, val in enumerate(row):
                if val:
                    for dy in range(ph):
                        for dx in range(pw):
                            put(start_x + c*pw + dx, start_y + r*ph + dy,
                                *text_color, 230)

    # Character bitmaps (5x7 grid)
    chars = {
        'G': [[1,1,1,1,1],[1,0,0,0,0],[1,0,0,0,0],[1,0,1,1,1],[1,0,0,0,1],[1,0,0,0,1],[1,1,1,1,1]],
        '0': [[0,1,1,1,0],[1,0,0,0,1],[1,0,0,1,1],[1,0,1,0,1],[1,1,0,0,1],[1,0,0,0,1],[0,1,1,1,0]],
        'D': [[1,1,1,1,0],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,1,1,1,0]],
        'M': [[1,0,0,0,1],[1,1,0,1,1],[1,0,1,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1]],
        '3': [[1,1,1,1,1],[0,0,0,0,1],[0,0,0,0,1],[0,1,1,1,1],[0,0,0,0,1],[0,0,0,0,1],[1,1,1,1,1]],
    }

    # Layout: G 0 D M 0 D 3
    text_str = "G0DM0D3"
    char_w = int(12 * s)
    gap = int(3 * s)
    total_w = len(text_str) * char_w + (len(text_str)-1) * gap
    start_x = (size - total_w) // 2
    for i, ch in enumerate(text_str):
        if ch in chars:
            draw_char_block(chars[ch], start_x + i*(char_w+gap), text_y, char_w, text_h)

    # Scanline effect (subtle)
    for y in range(0, size, max(1, int(3*s))):
        for x in range(size):
            old = px[y][x]
            px[y][x] = (max(0, old[0]-8), max(0, old[1]-8), max(0, old[2]-8), old[3])

    return px

# Generate icons at multiple sizes
out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'public')
os.makedirs(out_dir, exist_ok=True)

for icon_size in [192, 512]:
    pixels = generate_icon(icon_size)
    png_data = create_png(icon_size, icon_size, pixels)
    path = os.path.join(out_dir, f'icon-{icon_size}.png')
    with open(path, 'wb') as f:
        f.write(png_data)
    print(f'Generated {path} ({len(png_data)} bytes)')

# Also generate a 96px for Termux shortcut
pixels = generate_icon(96)
png_data = create_png(96, 96, pixels)
shortcut_icon = os.path.join(out_dir, 'icon-96.png')
with open(shortcut_icon, 'wb') as f:
    f.write(png_data)
print(f'Generated {shortcut_icon} ({len(png_data)} bytes)')

print('Done!')
