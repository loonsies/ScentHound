#!/usr/bin/env python3
# Used to create a basic texture to make line look a little nicer.
from PIL import Image

img = Image.open("dummy.png").convert("RGBA")
pixels = img.load()
import math

def distance(point1, point2):
    """
    Calculate the Euclidean distance between two points in 2D space.

    Parameters:
    - point1: tuple of (x1, y1)
    - point2: tuple of (x2, y2)

    Returns:
    - float: the distance between the two points
    """
    x1, y1 = point1
    x2, y2 = point2
    return math.sqrt((x2 - x1)**2 + (y2 - y1)**2)

minSize = 0.2
minAlpha = 40
maxAlpha = 255

halfY = img.height / 2
radius = halfY
calcWidth = img.width - halfY

# Precompute fade value at the seam to match both sides
startScaleX = 1 - (0 / calcWidth)  # offset = 0 at x = halfY
seamFade = int(minAlpha + ((maxAlpha - minAlpha) * startScaleX))  # full fade at start of taper

for x in range(img.width):
    if x < halfY:
        # Semicircle: use same fade as taper seam, scaled by circular distance
        for y in range(img.height):
            dx = x - radius
            dy = y - halfY
            dist = (dx**2 + dy**2)**0.5
            if dist > radius:
                a = 0
            else:
                a = int(seamFade * (1 - dist / radius))
            pixels[x, y] = (255, 255, 255, a)
    else:
        offset = x - halfY
        scaleX = 1 - (offset / calcWidth)
        fade = int(minAlpha + ((maxAlpha - minAlpha) * scaleX))
        for y in range(img.height):
            distY = abs(halfY - y) / halfY
            if (distY > scaleX) and (distY > minSize):
                a = 0
            else:
                a = int(fade * (1 - distY))
            pixels[x, y] = (255, 255, 255, a)

img.save("qtip.png")