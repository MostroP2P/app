import 'package:flutter/material.dart';

/// A `MaterialApp.builder` that renders the app at [scale] times the text
/// size, as the system setting would.
TransitionBuilder textScaleBuilder(double scale) =>
    (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    );
