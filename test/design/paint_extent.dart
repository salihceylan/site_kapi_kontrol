// Boyama kapsamı: bir RenderObject'in (alt ağacıyla) tuvale GERÇEKTE nereye boyadığı.
//
// `RenderObject.paintBounds` bunu söylemez: bir CustomPainter kendi sınırının dışına da çizebilir (Panel vitrininin eski
// düz zemini vitrinin bir ekran boyu üstüne / altına taşıyordu; kaydırma görünümü içerik sığınca kırpmadığından üstteki
// acil duyuru şeridini örtüyordu). Testler "şuranın dışına boyanmaz" iddiasını bununla, golden yerine geometriyle
// kanıtlar. Bu dosya `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tuvale çizilen tek şekil: yöntem (`#drawRect`, `#drawRRect`, ...), kırpma uygulanmış sınırı (kaydın kökü olan
/// nesnenin koordinatlarında) ve boyanın rengi (gradyanlı boyada varsayılan renk).
class PaintedShape {
  const PaintedShape(this.method, this.bounds, this.color);

  final Symbol method;
  final Rect bounds;
  final Color color;

  @override
  String toString() => '$method $bounds $color';
}

/// [outer], [inner]'ı tümüyle kapsıyor mu?
bool rectCovers(Rect outer, Rect inner) =>
    outer.left <= inner.left && outer.top <= inner.top && outer.right >= inner.right && outer.bottom >= inner.bottom;

/// [object]'i alt ağacıyla (tekrar boyama sınırları dahil) kayıt tuvaline boyar ve çizilen şekillerin sınırlarını
/// [object]'in kendi koordinatlarında döndürür (çizim sırasıyla).
///
/// save / saveLayer / restore / restoreToCount, translate / scale / rotate / transform ve kırpmalar (clipRect /
/// clipRRect / clipRSuperellipse / clipPath; kesişim olarak) izlenir: kırpılıp görünmeyen bölüm sayılmaz, tamamen
/// kırpılan şekil listede yoktur. Çizgi kalınlığı sınıra eklenir. Metin (drawParagraph), görüntü ve gölge sayılmaz.
List<PaintedShape> paintedShapes(RenderObject object) {
  final canvas = TestRecordingCanvas();
  object.paint(TestRecordingPaintingContext(canvas), Offset.zero);

  // (dönüşüm, kırpma) yığını; kırpma kökün koordinatlarındadır. Kayıt tuvalinin kayıt sayacı 0'dan başlar.
  final stack = <(Matrix4, Rect)>[(Matrix4.identity(), Rect.largest)];
  Matrix4 matrix() => stack.last.$1;
  Rect clip() => stack.last.$2;
  void apply(Matrix4 m) => matrix().multiply(m);
  void clipTo(Rect local) =>
      stack[stack.length - 1] = (matrix(), clip().intersect(MatrixUtils.transformRect(matrix(), local)));

  final shapes = <PaintedShape>[];
  void add(Symbol method, Rect global, Color color) {
    final visible = global.intersect(clip());
    if (visible.width > 0 && visible.height > 0) shapes.add(PaintedShape(method, visible, color));
  }

  void draw(Symbol method, Rect local, Paint paint, {bool stroked = false}) {
    final stroke = stroked || paint.style == PaintingStyle.stroke;
    final rect = stroke ? local.inflate(paint.strokeWidth / 2) : local;
    add(method, MatrixUtils.transformRect(matrix(), rect), paint.color);
  }

  for (final call in canvas.invocations) {
    final invocation = call.invocation;
    final a = invocation.positionalArguments;
    final method = invocation.memberName;
    switch (method) {
      case #save:
      case #saveLayer:
        stack.add((matrix().clone(), clip()));
      case #restore:
        if (stack.length > 1) stack.removeLast();
      case #restoreToCount:
        while (stack.length > 1 && stack.length - 1 > (a[0] as int)) {
          stack.removeLast();
        }
      case #translate:
        apply(Matrix4.translationValues(a[0] as double, a[1] as double, 0));
      case #scale:
        final sx = a[0] as double;
        final sy = a.length > 1 && a[1] != null ? a[1] as double : sx;
        apply(Matrix4.diagonal3Values(sx, sy, 1));
      case #rotate:
        apply(Matrix4.rotationZ(a[0] as double));
      case #transform:
        apply(Matrix4.fromFloat64List(a[0] as Float64List));
      case #clipRect:
        if (invocation.namedArguments[#clipOp] != ui.ClipOp.difference) clipTo(a[0] as Rect);
      case #clipRRect:
        clipTo((a[0] as RRect).outerRect);
      case #clipRSuperellipse:
        clipTo((a[0] as ui.RSuperellipse).outerRect);
      case #clipPath:
        clipTo((a[0] as Path).getBounds());
      case #drawRect:
      case #drawOval:
        draw(method, a[0] as Rect, a[1] as Paint);
      case #drawRRect:
        draw(method, (a[0] as RRect).outerRect, a[1] as Paint);
      case #drawDRRect:
        draw(method, (a[0] as RRect).outerRect, a[2] as Paint);
      case #drawRSuperellipse:
        draw(method, (a[0] as ui.RSuperellipse).outerRect, a[1] as Paint);
      case #drawPath:
        draw(method, (a[0] as Path).getBounds(), a[1] as Paint);
      case #drawCircle:
        draw(method, Rect.fromCircle(center: a[0] as Offset, radius: a[1] as double), a[2] as Paint);
      case #drawArc:
        draw(method, a[0] as Rect, a[4] as Paint);
      case #drawLine:
        draw(method, Rect.fromPoints(a[0] as Offset, a[1] as Offset), a[2] as Paint, stroked: true);
      case #drawPaint:
        add(method, Rect.largest, (a[0] as Paint).color);
      case #drawColor:
        add(method, Rect.largest, a[0] as Color);
    }
  }
  return shapes;
}

/// [object]'in tuvale çizdiklerinden kendi sınırının ([tolerance] dp pay) dışına taşanlar.
List<PaintedShape> paintedOutside(RenderBox object, {double tolerance = 0.5}) {
  final own = (Offset.zero & object.size).inflate(tolerance);
  return <PaintedShape>[
    for (final shape in paintedShapes(object))
      if (!rectCovers(own, shape.bounds)) shape,
  ];
}
