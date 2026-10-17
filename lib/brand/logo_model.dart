import 'dart:ui';

/// Logo vektör verisinin türleri. Veri `gude_logo_data.dart` içindedir (tool/logo/svg_to_dart.py üretir).
/// Yollar yalnızca mutlak M L C Z komutları içerir; [parseLogoPath] bunları Flutter [Path]'ine çevirir.
sealed class LogoFill {
  const LogoFill();

  /// [Paint.shader] için gradyan ([opacity] renklerin alfasıyla çarpılır); düz renkte null.
  Shader? shader([double opacity = 1]) => null;
}

class LogoSolid extends LogoFill {
  const LogoSolid(this.color);
  final Color color;
}

class LogoLinear extends LogoFill {
  const LogoLinear(this.x1, this.y1, this.x2, this.y2, this.offsets, this.colors);
  final double x1, y1, x2, y2;
  final List<double> offsets;
  final List<Color> colors;

  @override
  Shader shader([double opacity = 1]) => Gradient.linear(Offset(x1, y1), Offset(x2, y2), _faded(colors, opacity), offsets);
}

class LogoRadial extends LogoFill {
  const LogoRadial(this.cx, this.cy, this.r, this.fx, this.fy, this.offsets, this.colors);
  final double cx, cy, r, fx, fy;
  final List<double> offsets;
  final List<Color> colors;

  @override
  Shader shader([double opacity = 1]) =>
      Gradient.radial(Offset(cx, cy), r, _faded(colors, opacity), offsets, TileMode.clamp, null, Offset(fx, fy), 0);
}

List<Color> _faded(List<Color> colors, double opacity) =>
    opacity >= 1 ? colors : [for (final c in colors) c.withValues(alpha: c.a * opacity)];

/// Tek bir dolgulu yol. [opacity] dolgunun ek saydamlığıdır.
class LogoShape {
  const LogoShape(this.id, this.d, this.fill, {this.opacity = 1.0});
  final String id;
  final String d;
  final LogoFill fill;
  final double opacity;
}

/// "M x y L x y C x1 y1 x2 y2 x y Z" biçimindeki yol verisini çözer. Başka komut gelirse [FormatException] atar.
Path parseLogoPath(String d) {
  final path = Path();
  final tokens = d.split(' ');
  var i = 0;
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    final cmd = tokens[i++];
    switch (cmd) {
      case 'M':
        path.moveTo(next(), next());
      case 'L':
        path.lineTo(next(), next());
      case 'C':
        path.cubicTo(next(), next(), next(), next(), next(), next());
      case 'Z':
        path.close();
      case '':
        break;
      default:
        throw FormatException('logo yolunda desteklenmeyen komut: $cmd');
    }
  }
  return path;
}
