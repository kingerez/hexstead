import 'package:flutter/material.dart';

/// Rounded translucent backing so floating chrome stays readable over the
/// board art.
BoxDecoration chromePill() => BoxDecoration(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
    );
