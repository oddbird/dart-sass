// Copyright 2016 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:source_span/source_span.dart';

import '../../value/list.dart';
import '../../util/map.dart';
import 'expression.dart';
import 'expression/list.dart';
import 'node.dart';

/// A set of arguments passed in to a function or mixin.
///
/// {@category AST}
final class ArgumentList implements SassNode {
  /// The arguments passed by position.
  final List<Expression> positional;

  /// The arguments passed by name.
  final Map<String, Expression> named;

  /// The first rest argument (as in `$args...`).
  final Expression? rest;

  /// The second rest argument, which is expected to only contain a keyword map.
  final Expression? keywordRest;

  final FileSpan span;

  /// Returns whether this invocation passes no arguments.
  bool get isEmpty => positional.isEmpty && named.isEmpty && rest == null;

  ArgumentList(
    Iterable<Expression> positional,
    Map<String, Expression> named,
    this.span, {
    this.rest,
    this.keywordRest,
  })  : positional = List.unmodifiable(positional),
        named = Map.unmodifiable(named) {
    assert(rest != null || keywordRest == null);
  }

  /// Creates an invocation that passes no arguments.
  ArgumentList.empty(this.span)
      : positional = const [],
        named = const {},
        rest = null,
        keywordRest = null;

  String toString() {
    var components = [
      for (var argument in positional) _parenthesizeArgument(argument),
      for (var (name, value) in named.pairs)
        "\$$name: ${_parenthesizeArgument(value)}",
      if (rest case var rest?) "${_parenthesizeArgument(rest)}...",
      if (keywordRest case var keywordRest?)
        "${_parenthesizeArgument(keywordRest)}...",
    ];
    return "(${components.join(', ')})";
  }

  /// Wraps [argument] in parentheses if necessary.
  String _parenthesizeArgument(Expression argument) => switch (argument) {
        ListExpression(
          separator: ListSeparator.comma,
          hasBrackets: false,
          contents: [_, _, ...],
        ) =>
          "($argument)",
        _ => argument.toString(),
      };
}
