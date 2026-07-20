import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

final RegExp _mathPattern = RegExp(r'\$(.+?)\$');

/// Renders text that may contain inline TeX wrapped in single `$...$`
/// (exactly how AFAPS-Exam's source questions encode formulas). Plain
/// segments render as normal text; math segments render via KaTeX-style
/// typesetting. Malformed TeX falls back to showing the raw `$...$` chunk
/// instead of crashing — the source data is OCR/VLM-extracted and not
/// guaranteed to be perfectly well-formed.
class LatexText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  const LatexText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);

    if (!text.contains('\$')) {
      return Text(text, style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow);
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _mathPattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final expression = match.group(1)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Math.tex(
            expression,
            mathStyle: MathStyle.text,
            textStyle: effectiveStyle,
            onErrorFallback: (_) => Text('\$$expression\$', style: style),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
