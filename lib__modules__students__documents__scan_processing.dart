import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// How a scanned page is cleaned up.
enum ScanFilter {
  /// White paper, dark sharp text, shadows removed (best for certificates).
  clean,

  /// Greyscale with shadows evened out.
  grey,

  /// Colours kept, only straightened.
  colour,
}

/// A photo ready for the corner editor: upright, at most [maxWorkingSide]
/// pixels on its long side.
class ScanPhoto {
  const ScanPhoto(this.jpeg, this.width, this.height);

  final Uint8List jpeg;
  final int width;
  final int height;
}

const maxWorkingSide = 2600;
const maxPageSide = 2000;

/// Decodes a camera photo or picked image, turns it upright (EXIF) and
/// makes it a manageable size. Runs in a background isolate.
ScanPhoto prepareScanPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Not an image');
  var image = img.bakeOrientation(decoded);
  final long = math.max(image.width, image.height);
  if (long > maxWorkingSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxWorkingSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxWorkingSide, interpolation: img.Interpolation.average);
  }
  return ScanPhoto(Uint8List.fromList(img.encodeJpg(image, quality: 92)), image.width, image.height);
}

/// Turns the working photo a quarter turn clockwise.
ScanPhoto rotateScanPhoto(Uint8List jpeg) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) throw const FormatException('Not an image');
  final turned = img.copyRotate(decoded, angle: 90);
  return ScanPhoto(Uint8List.fromList(img.encodeJpg(turned, quality: 92)), turned.width, turned.height);
}

/// What to do with one page: the photo, the four page corners (as fractions
/// of width and height, in the order top-left, top-right, bottom-right,
/// bottom-left) and the clean-up.
class ScanJob {
  const ScanJob(this.jpeg, this.corners, this.filter);

  final Uint8List jpeg;
  final List<(double, double)> corners;
  final ScanFilter filter;
}

/// Cuts the page out along its corners, straightens it (true perspective
/// correction) and cleans it up. Returns a JPEG. Runs in a background isolate.
Uint8List processScan(ScanJob job) {
  final decoded = img.decodeImage(job.jpeg);
  if (decoded == null) throw const FormatException('Not an image');
  final src = decoded.convert(format: img.Format.uint8, numChannels: 3);
  final page = warpPage(src, job.corners);
  final out = switch (job.filter) {
    ScanFilter.colour => page,
    ScanFilter.grey => cleanUp(page, blackAndWhite: false),
    ScanFilter.clean => cleanUp(page, blackAndWhite: true),
  };
  return Uint8List.fromList(img.encodeJpg(out, quality: 88));
}

/// The page between [corners] (fractions; TL, TR, BR, BL), mapped to an
/// upright rectangle of about the page's real proportions.
img.Image warpPage(img.Image src, List<(double, double)> corners) {
  assert(corners.length == 4);
  final pts = [for (final (x, y) in corners) (x * (src.width - 1), y * (src.height - 1))];
  double dist((double, double) a, (double, double) b) => math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));
  var w = math.max(dist(pts[0], pts[1]), dist(pts[3], pts[2]));
  var h = math.max(dist(pts[0], pts[3]), dist(pts[1], pts[2]));
  if (w < 8 || h < 8) throw const FormatException('Page too small');
  final scale = math.min(1.0, maxPageSide / math.max(w, h));
  final outW = math.max(8, (w * scale).round());
  final outH = math.max(8, (h * scale).round());

  // Projective map from the unit square to the quad (Heckbert).
  final (x0, y0) = pts[0];
  final (x1, y1) = pts[1];
  final (x2, y2) = pts[2];
  final (x3, y3) = pts[3];
  final dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
  final dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
  double a, b, c, d, e, f, g, hh;
  final den = dx1 * dy2 - dx2 * dy1;
  if ((dx3.abs() < 1e-9 && dy3.abs() < 1e-9) || den.abs() < 1e-9) {
    a = x1 - x0;
    b = x2 - x1;
    c = x0;
    d = y1 - y0;
    e = y2 - y1;
    f = y0;
    g = 0;
    hh = 0;
  } else {
    g = (dx3 * dy2 - dx2 * dy3) / den;
    hh = (dx1 * dy3 - dx3 * dy1) / den;
    a = x1 - x0 + g * x1;
    b = x3 - x0 + hh * x3;
    c = x0;
    d = y1 - y0 + g * y1;
    e = y3 - y0 + hh * y3;
    f = y0;
  }

  final sw = src.width, sh = src.height;
  final s = src.getBytes(order: img.ChannelOrder.rgb);
  final o = Uint8List(outW * outH * 3);
  var k = 0;
  for (var y = 0; y < outH; y++) {
    final v = outH == 1 ? 0.0 : y / (outH - 1);
    for (var x = 0; x < outW; x++) {
      final u = outW == 1 ? 0.0 : x / (outW - 1);
      final z = g * u + hh * v + 1;
      var sx = (a * u + b * v + c) / z;
      var sy = (d * u + e * v + f) / z;
      if (sx < 0) sx = 0;
      if (sy < 0) sy = 0;
      if (sx > sw - 1) sx = (sw - 1).toDouble();
      if (sy > sh - 1) sy = (sh - 1).toDouble();
      final ix = sx.floor(), iy = sy.floor();
      final fx = sx - ix, fy = sy - iy;
      final ix1 = ix + 1 < sw ? ix + 1 : ix;
      final iy1 = iy + 1 < sh ? iy + 1 : iy;
      final p00 = (iy * sw + ix) * 3, p10 = (iy * sw + ix1) * 3;
      final p01 = (iy1 * sw + ix) * 3, p11 = (iy1 * sw + ix1) * 3;
      for (var ch = 0; ch < 3; ch++) {
        final top = s[p00 + ch] + (s[p10 + ch] - s[p00 + ch]) * fx;
        final bottom = s[p01 + ch] + (s[p11 + ch] - s[p01 + ch]) * fx;
        o[k++] = (top + (bottom - top) * fy).round();
      }
    }
  }
  return img.Image.fromBytes(width: outW, height: outH, bytes: o.buffer, numChannels: 3, order: img.ChannelOrder.rgb);
}

/// Evens out shadows and uneven light: each pixel is compared with the
/// paper's brightness around it. [blackAndWhite] then pushes the paper to
/// white and the writing to sharp black (photos stay readable as grey).
img.Image cleanUp(img.Image page, {required bool blackAndWhite}) {
  final w = page.width, h = page.height;
  final rgb = page.convert(format: img.Format.uint8, numChannels: 3).getBytes(order: img.ChannelOrder.rgb);
  final grey = Uint8List(w * h);
  for (var i = 0, j = 0; i < grey.length; i++, j += 3) {
    grey[i] = ((rgb[j] * 299 + rgb[j + 1] * 587 + rgb[j + 2] * 114) ~/ 1000);
  }

  // The paper's brightness in blocks: a bright percentile ignores the writing.
  final block = math.max(12, math.max(w, h) ~/ 36);
  final gw = (w + block - 1) ~/ block, gh = (h + block - 1) ~/ block;
  final paper = Float64List(gw * gh);
  final hist = Int32List(256);
  for (var by = 0; by < gh; by++) {
    for (var bx = 0; bx < gw; bx++) {
      hist.fillRange(0, 256, 0);
      var n = 0;
      final yEnd = math.min(h, (by + 1) * block), xEnd = math.min(w, (bx + 1) * block);
      for (var y = by * block; y < yEnd; y += 2) {
        for (var x = bx * block; x < xEnd; x += 2) {
          hist[grey[y * w + x]]++;
          n++;
        }
      }
      final target = (n * 0.9).ceil();
      var acc = 0, level = 255;
      for (var t = 0; t < 256; t++) {
        acc += hist[t];
        if (acc >= target) {
          level = t;
          break;
        }
      }
      paper[by * gw + bx] = math.max(40, level).toDouble();
    }
  }
  // Smooth the paper map so block edges never show.
  final smooth = Float64List(gw * gh);
  for (var by = 0; by < gh; by++) {
    for (var bx = 0; bx < gw; bx++) {
      var sum = 0.0, n = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final yy = by + dy, xx = bx + dx;
          if (yy < 0 || xx < 0 || yy >= gh || xx >= gw) continue;
          sum += paper[yy * gw + xx];
          n++;
        }
      }
      smooth[by * gw + bx] = sum / n;
    }
  }

  final out = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    final gy = ((y + 0.5) / block - 0.5).clamp(0.0, gh - 1.0);
    final y0 = gy.floor(), y1 = math.min(gh - 1, y0 + 1), fy = gy - y0;
    for (var x = 0; x < w; x++) {
      final gx = ((x + 0.5) / block - 0.5).clamp(0.0, gw - 1.0);
      final x0 = gx.floor(), x1 = math.min(gw - 1, x0 + 1), fx = gx - x0;
      final top = smooth[y0 * gw + x0] + (smooth[y0 * gw + x1] - smooth[y0 * gw + x0]) * fx;
      final bottom = smooth[y1 * gw + x0] + (smooth[y1 * gw + x1] - smooth[y1 * gw + x0]) * fx;
      final bg = top + (bottom - top) * fy;
      var n = grey[y * w + x] / bg; // 1.0 = paper
      if (n > 1) n = 1;
      double v;
      if (blackAndWhite) {
        // Paper white, writing black, with a short soft edge for smooth letters.
        v = ((n - 0.55) / (0.85 - 0.55)).clamp(0.0, 1.0).toDouble();
        v = v * v * (3 - 2 * v);
      } else {
        v = ((n - 0.15) / (0.95 - 0.15)).clamp(0.0, 1.0).toDouble();
      }
      final level = (v * 255).round();
      final k = (y * w + x) * 3;
      out[k] = level;
      out[k + 1] = level;
      out[k + 2] = level;
    }
  }
  return img.Image.fromBytes(width: w, height: h, bytes: out.buffer, numChannels: 3, order: img.ChannelOrder.rgb);
}

/// Where the page probably is: the four corners of the paper, found as the
/// bright area that stands out from the background. Falls back to a frame
/// just inside the photo when nothing clear is found.
List<(double, double)> guessCorners(Uint8List jpeg) {
  const fallback = [(0.06, 0.06), (0.94, 0.06), (0.94, 0.94), (0.06, 0.94)];
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) return fallback;
  final small = img.copyResize(decoded, width: decoded.width >= decoded.height ? 160 : null, height: decoded.width < decoded.height ? 160 : null);
  final w = small.width, h = small.height;
  final g = Uint8List(w * h);
  var sum = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      final v = (p.r * 299 + p.g * 587 + p.b * 114) ~/ 1000;
      g[y * w + x] = v.toInt();
      sum += v.toInt();
    }
  }
  final mean = sum / g.length;
  // Paper: clearly brighter than the average of the whole photo.
  final limit = mean + 12;
  // Extreme points of the bright region along the diagonals.
  var tl = (0, 0), tr = (0, 0), br = (0, 0), bl = (0, 0);
  double? sTl, sTr, sBr, sBl;
  var count = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (g[y * w + x] < limit) continue;
      count++;
      final s1 = (x + y).toDouble(), s2 = (x - y).toDouble();
      if (sTl == null || s1 < sTl) {
        sTl = s1;
        tl = (x, y);
      }
      if (sBr == null || s1 > sBr) {
        sBr = s1;
        br = (x, y);
      }
      if (sTr == null || s2 > sTr) {
        sTr = s2;
        tr = (x, y);
      }
      if (sBl == null || s2 < sBl) {
        sBl = s2;
        bl = (x, y);
      }
    }
  }
  // Too little or almost everything bright: no clear page edge.
  if (count < g.length * 0.15 || count > g.length * 0.97) return fallback;
  (double, double) frac((int, int) p) =>
      ((p.$1 / (w - 1)).clamp(0.0, 1.0).toDouble(), (p.$2 / (h - 1)).clamp(0.0, 1.0).toDouble());
  final corners = [frac(tl), frac(tr), frac(br), frac(bl)];
  // Sanity: a real page spans a good part of the photo.
  final spanX = math.max(corners[1].$1, corners[2].$1) - math.min(corners[0].$1, corners[3].$1);
  final spanY = math.max(corners[2].$2, corners[3].$2) - math.min(corners[0].$2, corners[1].$2);
  if (spanX < 0.3 || spanY < 0.3) return fallback;
  return corners;
}
